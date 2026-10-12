import Foundation
import MideaProtocol
import Observation

/// 空调状态源：把设备上报映射成可观察状态，把用户操作转成命令（乐观更新）。
@Observable
final class ACStore {
    private(set) var link: LinkState = .starting
    private(set) var sn = ""
    private(set) var hasStatus = false

    private(set) var power = false
    private(set) var modeCode = ACMode.cool.rawValue
    private(set) var temp = 26.0
    private(set) var fanCode = FanSpeed.auto.rawValue
    private(set) var airflow = Airflow.fixed
    private(set) var eco = false
    private(set) var strong = false
    private(set) var indoor: Double?
    private(set) var outdoor: Double?
    private(set) var fault = false

    var beep: Bool {
        didSet {
            UserDefaults.standard.set(beep, forKey: "beep")
            device.beep = beep
        }
    }

    var mode: ACMode? { ACMode(rawValue: modeCode) }
    var fan: FanSpeed? { FanSpeed(rawValue: fanCode) }

    /// 模式展示名；设备可能处于面板上没有的模式（如遥控器设的智能除湿）。
    var modeLabel: String { mode?.label ?? (modeCode == 6 ? String(localized: "智能除湿") : "\(modeCode)") }
    /// 风速展示名；非标准档位（设备自动调档）显示原始百分比。
    var fanLabel: String { fan?.label ?? "\(fanCode)%" }

    private let device = ACLink()
    private var tempDebounce: Task<Void, Never>?
    /// 用户拖动温度后、设备确认前，忽略设备回报的旧温度，避免滑块回弹。
    private var tempPending = false
    private var tempSent = false

    init() {
        beep = UserDefaults.standard.object(forKey: "beep") as? Bool ?? true
        device.beep = beep
        device.onState = { [weak self] in self?.handle($0) }
        device.onStatus = { [weak self] in self?.handle($0) }
        device.connect()
    }

    func shutdown() { device.disconnect() }

    // MARK: - 用户操作

    func reconnect() { device.connect() }

    func refresh() { device.refresh() }

    func togglePower() {
        power.toggle()
        device.send(.power(power))
    }

    func setMode(_ m: ACMode) {
        modeCode = m.rawValue
        device.send(.mode(m))
    }

    func setFan(_ f: FanSpeed) {
        fanCode = f.rawValue
        device.send(.fan(f))
    }

    func setAirflow(_ a: Airflow) {
        airflow = a
        device.send(.swing(upDown: a.ud, leftRight: a.lr))
    }

    func toggleEco() {
        eco.toggle()
        device.send(.eco(eco))
    }

    func toggleStrong() {
        strong.toggle()
        device.send(.strong(strong))
    }

    /// 立即更新界面，停手 0.6s 后才下发，避免拖动时连发控制帧。
    func setTemp(_ value: Double) {
        let v = min(max((value / TempRange.step).rounded() * TempRange.step, TempRange.min), TempRange.max)
        guard v != temp else { return }
        temp = v
        tempPending = true
        tempSent = false
        tempDebounce?.cancel()
        tempDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.device.send(.temperature(self.temp))
            self.tempSent = true
        }
    }

    func stepTemp(_ delta: Double) { setTemp(temp + delta) }

    // MARK: - 设备事件

    private func handle(_ state: LinkState) {
        link = state
        sn = device.sn
        switch state {
        case .connected:
            if tempSent { tempPending = false }
        case .failed:
            tempPending = false
        default:
            break
        }
    }

    private func handle(_ s: ACStatus) {
        hasStatus = true
        power = s.power
        modeCode = s.mode
        if s.temperature == temp { tempPending = false }
        if !tempPending { temp = s.temperature }
        fanCode = s.fanSpeed
        airflow = Airflow(ud: s.swingUpDown, lr: s.swingLeftRight)
        eco = s.eco
        strong = s.strong
        indoor = s.indoor
        outdoor = s.outdoor
        fault = s.fault
    }
}
