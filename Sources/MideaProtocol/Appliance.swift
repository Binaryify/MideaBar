/// 美的家电帧（空调，设备类型 0xAC）：控制帧 0x40、查询帧 0x41、状态回包 0xC0。
///
/// 帧格式：`AA LEN AC 00×5 PROTO MSG OPCODE 数据… CRC8 SUM`，
/// CRC8 覆盖从 OPCODE 起的数据段，SUM 覆盖 LEN 到 CRC8。

/// 运行模式（协议码）。
public enum ACMode: UInt8, CaseIterable {
    case auto = 1, cool, dry, heat, fan
}

/// 风速档位（协议码，即风速百分比）。设备自动调档时可能上报其他数值。
public enum FanSpeed: UInt8, CaseIterable {
    case auto = 102, low = 40, mid = 60, high = 80, full = 100
}

/// 用户操作。
public enum ACCommand: Equatable {
    case power(Bool)
    case mode(ACMode)
    case temperature(Double)
    case fan(FanSpeed)
    case swing(upDown: Bool, leftRight: Bool)
    case eco(Bool)
    case strong(Bool)
}

/// 设备上报的状态。
public struct ACStatus: Equatable {
    public var power = false
    public var fault = false
    /// 模式协议码，可能不在 `ACMode` 里（如 6 = 智能除湿）。
    public var mode: UInt8 = 0
    public var temperature = 0.0
    /// 风速协议码，可能不在 `FanSpeed` 里。
    public var fanSpeed: UInt8 = 0
    public var swingUpDown = false
    public var swingLeftRight = false
    public var eco = false
    public var strong = false
    public var electricHeat = false
    public var temperature2 = 0.0
    /// 室内 / 室外温度；传感器无读数（原始值 0xFF，如外机停机时）为 nil。
    public var indoor: Double?
    public var outdoor: Double?
}

/// 控制帧要下发的完整状态。控制是「读-改-写」：先灌入设备状态，再改目标字段，整帧下发，
/// 避免把没改的设置冲掉。未建模的字段（定时、睡眠曲线等）按协议默认值编码。
public struct ACState: Equatable {
    public var power = false
    public var beep = true
    public var mode = ACMode.cool.rawValue
    public var temperature = 26.0
    public var fanSpeed = FanSpeed.auto.rawValue
    public var swingUpDown = false
    public var swingLeftRight = false
    public var eco = false
    public var strong = false
    public var electricHeat = false
    /// 第二温控，设定温度时与 temperature 同步。
    public var temperature2 = 26.0

    public init() {}

    public mutating func apply(_ status: ACStatus) {
        power = status.power
        mode = status.mode
        temperature = status.temperature
        fanSpeed = status.fanSpeed
        swingUpDown = status.swingUpDown
        swingLeftRight = status.swingLeftRight
        eco = status.eco
        strong = status.strong
        electricHeat = status.electricHeat
        if status.temperature2 > 0 { temperature2 = status.temperature2 }
    }

    public mutating func apply(_ command: ACCommand) {
        switch command {
        case .power(let on): power = on
        case .mode(let m): mode = m.rawValue
        case .temperature(let t): temperature = t; temperature2 = t
        case .fan(let f): fanSpeed = f.rawValue
        case .swing(let ud, let lr): swingUpDown = ud; swingLeftRight = lr
        case .eco(let on): eco = on
        case .strong(let on): strong = on
        }
    }
}

public enum Appliance {
    /// 控制帧（0x40，37 字节）。`order` 为 1...255 循环的帧序号。
    public static func controlFrame(_ s: ACState, order: UInt8) -> [UInt8] {
        var a = [UInt8](repeating: 0, count: 37)
        a[0] = 0xAA
        a[1] = 36
        a[2] = 0xAC
        a[8] = 2
        a[9] = 2 // 控制
        a[10] = 0x40
        // bit6 蜂鸣、bit1 控制来源（恒为 1）、bit0 开关机
        a[11] = s.beep.bit << 6 | 1 << 1 | s.power.bit
        // bit5-7 模式、bit0-3 温度整数部分 - 16、bit4 半度
        let tenths = Int((s.temperature * 10).rounded())
        a[12] = (s.mode & 7) << 5
        if (160...300).contains(tenths) { a[12] |= UInt8((tenths / 10 - 16) & 15) }
        if tenths % 10 == 5 { a[12] |= 16 }
        a[13] = s.fanSpeed & 127
        // 定时：未启用
        a[14] = 127
        a[15] = 127
        a[16] = 255
        // 扫风：0x30 基值，上下 0x0C，左右 0x03
        a[17] = 0x30 | (s.swingUpDown ? 0x0C : 0) | (s.swingLeftRight ? 0x03 : 0)
        a[18] = s.strong.bit << 5
        a[19] = s.electricHeat.bit << 3 | s.eco.bit << 7
        // 睡眠曲线 10 个点，默认均为 26℃：(26-17) | (26-17)<<4
        for i in 21...25 { a[i] = 0x99 }
        a[27] = 10 // 舒睡时长默认 10
        a[28] = UInt8((Int((s.temperature2 * 10 + 0.5).rounded()) / 10 - 12) & 31)
        a[29] = 128
        a[34] = order
        a[35] = crc8(a[10..<35])
        a[36] = Frames.negSum(a[1..<36])
        return a
    }

    /// 查询帧（0x41，24 字节）。
    public static func queryFrame(order: UInt8) -> [UInt8] {
        var a: [UInt8] = [0xAA, 23, 0xAC, 0, 0, 0, 0, 0, 0, 3, 0x41, 33, 0, 255, 3, 255, 0, 2, 0, 0, 0, order, 0, 0]
        a[22] = crc8(a[10..<22])
        a[23] = Frames.negSum(a[1..<23])
        return a
    }

    /// 解析状态回包（0xC0）。不是状态帧或校验不过时返回 nil。
    public static func parseStatus(_ t: [UInt8]) -> ACStatus? {
        guard t.count >= 27, t[0] == 0xAA, Int(t[1]) + 1 <= t.count, t[10] == 0xC0,
              Frames.negSum(t[1...Int(t[1])]) == 0
        else { return nil }
        let s = Array(t[10...])
        var st = ACStatus()
        st.power = s[1] & 0x01 != 0
        st.fault = s[1] & 0x80 != 0
        st.mode = s[2] >> 5
        let half = s[2] & 0x10 != 0
        st.temperature = Double(16 + (s[2] & 15)) + (half ? 0.5 : 0)
        st.fanSpeed = s[3]
        if s[7] & 0xF0 == 0x30 {
            st.swingLeftRight = s[7] & 0x03 != 0
            st.swingUpDown = s[7] & 0x0C != 0
        }
        st.strong = s[8] & 0x20 != 0
        st.electricHeat = s[9] & 0x08 != 0
        st.eco = s[9] & 0x10 != 0
        // 室内：(x-50)/2 取整后加 S[15] 低半字节的小数位；室外：(x-50)/2 加高半字节
        if s[11] != 0xFF {
            var indoor = ((Double(s[11]) - 50) / 2).rounded(.towardZero)
            indoor += (indoor < 0 ? -0.1 : 0.1) * Double(s[15] & 15)
            st.indoor = round1(indoor)
        }
        if s[12] != 0xFF {
            st.outdoor = round1((Double(s[12]) - 50) / 2 + 0.1 * Double(s[15] >> 4))
        }
        st.temperature2 = Double(12 + (s[13] & 31)) + (half ? 0.5 : 0)
        return st
    }

    private static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    /// CRC-8/854（多项式 0x31 反射，即 Dallas/Maxim）。
    static func crc8<C: Collection<UInt8>>(_ bytes: C) -> UInt8 {
        bytes.reduce(0) { crc8Table[Int($0 ^ $1)] }
    }

    private static let crc8Table: [UInt8] = (0...255).map { i in
        var c = UInt8(i)
        for _ in 0..<8 { c = c & 1 != 0 ? (c >> 1) ^ 0x8C : c >> 1 }
        return c
    }
}

private extension Bool {
    var bit: UInt8 { self ? 1 : 0 }
}
