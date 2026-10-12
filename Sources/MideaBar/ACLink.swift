import CoreBluetooth
import MideaProtocol
import os

/// 用 CoreBluetooth 直连空调：扫描 → 连接 → 握手 → 收发业务帧，断线自动重连。
/// 协议的字节层在 MideaProtocol 里，这里只管蓝牙与时序。所有回调都在主线程。
final class ACLink: NSObject {
    var onState: ((LinkState) -> Void)?
    var onStatus: ((ACStatus) -> Void)?
    private(set) var sn = ""
    /// 控制时空调是否蜂鸣（随控制帧下发）。
    var beep = true { didSet { state.beep = beep } }

    private enum Phase { case idle, scanning, connecting, c1, c2, c3, ready }
    private enum Job { case query, control(ACCommand) }

    private static let service = CBUUID(string: "FFA0")
    private static let writeUUID = CBUUID(string: "FFA1")
    private static let notifyUUID = CBUUID(string: "FFA2")
    private static let knownSNKey = "deviceSN"
    private let log = Logger(subsystem: "com.github.binaryify.mideabar", category: "ble")

    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var phase = Phase.idle
    /// 每次（重新）连接自增，让上一轮的定时器自动作废。
    private var generation = 0
    private var wantsConnection = false

    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var device: Advertisement?
    private var candidates: [UUID: (peripheral: CBPeripheral, ad: Advertisement, rssi: Int)] = [:]
    private var channel: SecureChannel?

    private var state = ACState()
    private var order: UInt8 = 0
    private var jobs: [Job] = []
    private var currentJob: Int?   // 当前任务的 generation 内序号，用来认领回包
    private var jobCounter = 0

    // MARK: - 对外接口

    func connect() {
        wantsConnection = true
        restart()
        guard central.state == .poweredOn else { return centralStateChanged() }
        startScan()
    }

    func disconnect() {
        wantsConnection = false
        restart()
    }

    func refresh() {
        guard phase == .ready else { return }
        if !jobs.contains(where: { if case .query = $0 { true } else { false } }) { enqueue(.query) }
    }

    func send(_ command: ACCommand) {
        guard phase == .ready else {
            // 没连上时丢弃命令；界面的乐观更新会在重连后被设备真实状态覆盖
            if phase == .idle { connect() }
            return
        }
        enqueue(.control(command))
    }

    // MARK: - 扫描与连接

    /// 作废当前连接与定时器，回到 idle。
    private func restart() {
        generation += 1
        if central.isScanning { central.stopScan() }
        if let p = peripheral {
            peripheral = nil
            central.cancelPeripheralConnection(p)
        }
        phase = .idle
        writeChar = nil
        channel = nil
        jobs = []
        currentJob = nil
    }

    /// 扫描 8 秒，优先上次连过的那台（看到就立即连接），否则选信号最强的。
    private func startScan() {
        phase = .scanning
        candidates = [:]
        onState?(.connecting)
        log.info("开始扫描")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        after(8) { [self] in
            guard phase == .scanning else { return }
            central.stopScan()
            guard let best = candidates.values.max(by: { $0.rssi < $1.rssi }) else {
                return fail(String(localized: "附近没有发现美的空调"))
            }
            connect(best.peripheral, best.ad)
        }
    }

    private func connect(_ p: CBPeripheral, _ ad: Advertisement) {
        central.stopScan()
        log.info("连接 \(ad.sn, privacy: .public)")
        phase = .connecting
        peripheral = p
        device = ad
        sn = ad.sn
        p.delegate = self
        central.connect(p)
        after(15) { [self] in
            if phase == .connecting { fail(String(localized: "连接超时")) }
        }
    }

    // MARK: - 握手

    private func startHandshake() {
        guard let device else { return }
        channel = SecureChannel(advertisData: device.advertisData)
        phase = .c1
        log.info("握手 c1")
        // 设备常忽略新连接的前一两个 c1：每次发全新的帧，直到它回应
        pump(.c1, every: 1.5, times: 15) { [self] in channel?.makeC1() }
        after(30) { [self] in
            if [.c1, .c2, .c3].contains(phase) { fail(String(localized: "握手超时")) }
        }
    }

    private func handle(_ inbound: SecureChannel.Inbound) {
        switch inbound {
        case .c1 where phase == .c1:
            guard let frame = channel?.makeC2() else { return }
            phase = .c2
            log.info("握手 c2")
            // 设备每收一个 c2 就换一对密钥，重发必须是同一帧
            pump(.c2, every: 1.2, times: 8) { frame }
        case .c2(let peerKey) where phase == .c2:
            guard let channel else { return }
            do {
                try channel.acceptPeerKey(peerKey)
            } catch {
                return fail(String(localized: "设备公钥无效"))
            }
            let frame = channel.makeC3()
            phase = .c3
            log.info("握手 c3")
            pump(.c3, every: 1.2, times: 8) { frame }
        case .c3(let result) where phase == .c3:
            guard result == 1 else { return fail(String(localized: "握手失败：密钥校验未通过")) }
            log.info("握手完成")
            phase = .ready
            UserDefaults.standard.set(sn, forKey: Self.knownSNKey)
            onState?(.connected)
            enqueue(.query)
        case .biz(let frame):
            guard let status = Appliance.parseStatus(frame) else { return }
            log.info("状态 开机=\(status.power) 模式=\(status.mode) 设定=\(status.temperature) 风速=\(status.fanSpeed) 室内=\(String(describing: status.indoor), privacy: .public) 室外=\(String(describing: status.outdoor), privacy: .public)")
            state.apply(status)
            onStatus?(status)
            finishJob()
        case .securityError(let code):
            log.error("设备返回错误 \(code.map { String(format: "%02x", $0) }.joined(), privacy: .public)")
        case .malformed(let reason):
            log.error("解析失败: \(reason, privacy: .public)")
        default:
            break
        }
    }

    // MARK: - 业务命令（串行执行）

    private func enqueue(_ job: Job) {
        jobs.append(job)
        runNextJob()
    }

    /// 发出命令后等任意一条状态回包作为应答。设备常丢第一帧、且对连续的帧去抖约 550ms，
    /// 所以 0.15s 后先补发一次，之后每秒重发，最多 6 次；同一命令重发不改内容，只换序号。
    private func runNextJob() {
        guard currentJob == nil, phase == .ready, !jobs.isEmpty, let channel else { return }
        let job = jobs.removeFirst()
        order = order == 255 ? 1 : order + 1
        let appliance: [UInt8]
        switch job {
        case .query:
            appliance = Appliance.queryFrame(order: order)
        case .control(let command):
            onState?(.syncing)
            state.apply(command)
            appliance = Appliance.controlFrame(state, order: order)
        }
        jobCounter += 1
        let id = jobCounter
        currentJob = id
        let delays = [0, 0.15, 1.15, 2.15, 3.15, 4.15]
        for (i, delay) in delays.enumerated() {
            after(delay) { [self] in
                guard currentJob == id else { return }
                write(channel.makeBiz(appliance))
                if i == delays.count - 1 {
                    after(1.5) { [self] in
                        if currentJob == id { fail(String(localized: "空调没有响应")) }
                    }
                }
            }
        }
    }

    private func finishJob() {
        guard currentJob != nil else { return }
        currentJob = nil
        onState?(.connected)
        runNextJob()
    }

    // MARK: - 工具

    private func write(_ frame: [UInt8]) {
        guard let peripheral, let writeChar else { return }
        // FFA1 只认带回执的写入，无回执写入会被静默丢弃
        peripheral.writeValue(Data(frame), for: writeChar, type: .withResponse)
    }

    /// 在 phase 不变期间按间隔重复发送。
    private func pump(_ phase: Phase, every interval: Double, times: Int, frame: @escaping () -> [UInt8]?) {
        for i in 0..<times {
            after(Double(i) * interval) { [self] in
                if self.phase == phase, let f = frame() { write(f) }
            }
        }
    }

    /// 延时执行；期间发生过重连则不执行。
    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.generation == gen { work() }
        }
    }

    /// 报错并断开，5 秒后自动重连。
    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        restart()
        onState?(.failed(message))
        after(5) { [self] in
            if wantsConnection, phase == .idle { connect() }
        }
    }

    private func centralStateChanged() {
        switch central.state {
        case .poweredOn:
            if wantsConnection, phase == .idle { connect() }
        case .poweredOff:
            restart()
            onState?(.failed(String(localized: "蓝牙已关闭")))
        case .unauthorized:
            onState?(.failed(String(localized: "没有蓝牙权限，请在「系统设置 › 隐私与安全性 › 蓝牙」中允许 MideaBar")))
        case .unsupported:
            onState?(.failed(String(localized: "这台 Mac 不支持低功耗蓝牙")))
        default:
            onState?(.starting)
        }
    }
}

// MARK: - CoreBluetooth 回调

extension ACLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) { centralStateChanged() }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard phase == .scanning,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let ad = Advertisement(manufacturerData: Array(data))
        else { return }
        if ad.sn == UserDefaults.standard.string(forKey: Self.knownSNKey) {
            return connect(p, ad)
        }
        candidates[p.identifier] = (p, ad, rssi.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p == peripheral else { return }
        p.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard p == peripheral else { return }
        fail(error.map { String(localized: "连接失败：\($0.localizedDescription)") } ?? String(localized: "连接失败"))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p == peripheral else { return } // 自己主动断开的已在 restart 里清掉
        fail(String(localized: "连接已断开"))
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == Self.service }) else {
            return fail(String(localized: "设备不支持该协议（未找到 FFA0 服务）"))
        }
        p.discoverCharacteristics([Self.writeUUID, Self.notifyUUID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let chars = service.characteristics ?? []
        guard let w = chars.first(where: { $0.uuid == Self.writeUUID }),
              let n = chars.first(where: { $0.uuid == Self.notifyUUID })
        else { return fail(String(localized: "设备不支持该协议（未找到 FFA1/FFA2 特征）")) }
        writeChar = w
        p.setNotifyValue(true, for: n)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.notifyUUID, phase == .connecting else { return }
        guard c.isNotifying else { return fail(String(localized: "订阅设备通知失败")) }
        after(0.3) { [self] in startHandshake() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.notifyUUID, let value = c.value, let channel else { return }
        channel.feed(Array(value)).forEach(handle)
    }
}
