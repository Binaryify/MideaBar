import SwiftUI

/// 运行模式；rawValue 即 agent 协议里的名称。
enum ACMode: String, CaseIterable, Identifiable {
    case auto, cool, dry, heat, fan
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: String(localized: "自动")
        case .cool: String(localized: "制冷")
        case .dry: String(localized: "除湿")
        case .heat: String(localized: "制热")
        case .fan: String(localized: "送风")
        }
    }

    var symbol: String {
        switch self {
        case .auto: "a.circle"
        case .cool: "snowflake"
        case .dry: "drop"
        case .heat: "sun.max"
        case .fan: "wind"
        }
    }

    /// 出风动画的色调。
    var airTint: Color {
        switch self {
        case .cool: Color(red: 0.80, green: 0.90, blue: 1.0)
        case .heat: Color(red: 1.0, green: 0.78, blue: 0.55)
        case .dry: Color(red: 0.70, green: 0.95, blue: 0.95)
        case .auto, .fan: Color.white
        }
    }
}

/// 风速；rawValue 即 agent 协议里的名称。
enum FanSpeed: String, CaseIterable, Identifiable {
    case auto, low, mid, high, full
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: String(localized: "自动")
        case .low: String(localized: "低风")
        case .mid: String(localized: "中风")
        case .high: String(localized: "高风")
        case .full: String(localized: "强风")
        }
    }
}

/// 扫风组合（上下 / 左右）。
enum Airflow: CaseIterable, Identifiable {
    case fixed, vertical, horizontal, both
    var id: Self { self }

    init(ud: Bool, lr: Bool) {
        switch (ud, lr) {
        case (true, true): self = .both
        case (true, false): self = .vertical
        case (false, true): self = .horizontal
        case (false, false): self = .fixed
        }
    }

    var ud: Bool { self == .vertical || self == .both }
    var lr: Bool { self == .horizontal || self == .both }

    var label: String {
        switch self {
        case .fixed: String(localized: "固定")
        case .vertical: String(localized: "上下")
        case .horizontal: String(localized: "左右")
        case .both: String(localized: "全向")
        }
    }
}

/// 设备连接状态（对应 agent 的 link 事件）。
enum LinkState: Equatable {
    case starting, connecting, connected, syncing
    case failed(String)

    /// failed 的 msg 来自 agent，原样展示，不做翻译。
    var label: String {
        switch self {
        case .starting: String(localized: "启动中…")
        case .connecting: String(localized: "连接中…")
        case .connected: String(localized: "已连接")
        case .syncing: String(localized: "同步中…")
        case .failed(let msg): msg
        }
    }

    var isBusy: Bool { self == .starting || self == .connecting || self == .syncing }
}

/// 设备可设定温度范围（协议限制 16~30℃，步进 0.5）。
enum TempRange {
    static let min = 16.0
    static let max = 30.0
    static let step = 0.5
}
