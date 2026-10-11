import Foundation
import Observation

/// 空调状态源：把 agent 事件映射成可观察状态，把用户操作转成命令（乐观更新）。
@Observable
final class ACStore {
    private(set) var link: LinkState = .starting
    private(set) var sn = ""
    private(set) var hasStatus = false

    private(set) var power = false
    private(set) var modeName = "cool"
    private(set) var temp = 26.0
    private(set) var fanName = "auto"
    private(set) var fanCode = 102
    private(set) var airflow = Airflow.fixed
    private(set) var eco = false
    private(set) var strong = false
    private(set) var indoor: Double?
    private(set) var outdoor: Double?
    private(set) var fault = false

    var beep: Bool {
        didSet {
            UserDefaults.standard.set(beep, forKey: "beep")
            agent.send(["op": "beep", "on": beep])
        }
    }

    var mode: ACMode? { ACMode(rawValue: modeName) }
    var fan: FanSpeed? { FanSpeed(rawValue: fanName) }

    /// 风速展示名；非标准档位（设备自动调档）显示原始百分比。
    var fanLabel: String { fan?.label ?? "\(fanCode)%" }

    private let agent = AgentClient()
    private var tempDebounce: Task<Void, Never>?
    /// 用户拖动温度后、设备确认前，忽略设备回报的旧温度，避免滑块回弹。
    private var tempPending = false
    private var tempSent = false

    init() {
        beep = UserDefaults.standard.object(forKey: "beep") as? Bool ?? true
        agent.onEvent = { [weak self] in self?.handle($0) }
        agent.onExit = { [weak self] in
            self?.link = .failed("后台进程已退出，正在重启…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.launch() }
        }
        launch()
    }

    private func launch() {
        do {
            try agent.start()
            agent.send(["op": "beep", "on": beep])
            reconnect()
        } catch {
            link = .failed(error.localizedDescription)
        }
    }

    func shutdown() { agent.stop() }

    // MARK: - 用户操作

    func reconnect() { agent.send(["op": "connect", "sn": sn]) }

    func refresh() {
        if link == .connected { agent.send(["op": "refresh"]) }
    }

    func togglePower() {
        power.toggle()
        agent.send(["op": "power", "on": power])
    }

    func setMode(_ m: ACMode) {
        modeName = m.rawValue
        agent.send(["op": "mode", "value": m.rawValue])
    }

    func setFan(_ f: FanSpeed) {
        fanName = f.rawValue
        agent.send(["op": "fan", "value": f.rawValue])
    }

    func setAirflow(_ a: Airflow) {
        airflow = a
        agent.send(["op": "swing", "ud": a.ud, "lr": a.lr])
    }

    func toggleEco() {
        eco.toggle()
        agent.send(["op": "eco", "on": eco])
    }

    func toggleStrong() {
        strong.toggle()
        agent.send(["op": "strong", "on": strong])
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
            self.agent.send(["op": "temp", "temp": self.temp])
            self.tempSent = true
        }
    }

    func stepTemp(_ delta: Double) { setTemp(temp + delta) }

    // MARK: - 事件

    private func handle(_ e: AgentClient.Event) {
        switch e.type {
        case "link":
            if let s = e.sn, !s.isEmpty { sn = s }
            switch e.state {
            case "connecting": link = .connecting
            case "connected":
                link = .connected
                if tempSent { tempPending = false }
            case "syncing": link = .syncing
            default:
                link = .failed(e.message ?? "未知错误")
                tempPending = false
            }
        case "status":
            hasStatus = true
            power = e.power ?? power
            modeName = e.mode ?? modeName
            if let t = e.temp {
                if t == temp { tempPending = false }
                if !tempPending { temp = t }
            }
            fanName = e.fan ?? fanName
            fanCode = e.fanCode ?? fanCode
            airflow = Airflow(ud: e.swingUD ?? false, lr: e.swingLR ?? false)
            eco = e.eco ?? eco
            strong = e.strong ?? strong
            indoor = e.indoor
            outdoor = e.outdoor
            fault = e.fault ?? false
        default:
            break
        }
    }
}
