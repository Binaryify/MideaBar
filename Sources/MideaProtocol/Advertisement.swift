/// 美的空调的蓝牙广播（厂商 ID 0x06A8）。
///
/// 厂商数据（不含 2 字节厂商 ID）：`01 | SN(14 字节 ASCII) | 01 03 00 32 | MAC(6) | 00`。
/// macOS 不暴露真实 MAC，握手所需的 advertisData 只能从这里重建。
public struct Advertisement: Equatable {
    public static let companyID: UInt16 = 0x06A8

    public let sn: String
    /// HKDF 的输入：0xAC ‖ SN 前 8 字节 ‖ MAC（倒序），共 15 字节。
    public let advertisData: [UInt8]

    /// - Parameter manufacturerData: CoreBluetooth 给出的厂商数据，前 2 字节为小端厂商 ID。
    ///   广播可能分包，需收到 ≥25 字节的完整包（含 MAC）才能解析，否则返回 nil。
    public init?(manufacturerData: [UInt8]) {
        guard manufacturerData.count >= 2,
              UInt16(manufacturerData[0]) | UInt16(manufacturerData[1]) << 8 == Self.companyID
        else { return nil }
        let p = Array(manufacturerData.dropFirst(2))
        guard p.count >= 25, p[0] == 0x01 else { return nil }
        sn = String(decoding: p[1..<15], as: UTF8.self)
        advertisData = [0xAC] + p[1..<9] + p[19..<25].reversed()
    }

    public init(sn: String, advertisData: [UInt8]) {
        self.sn = sn
        self.advertisData = advertisData
    }
}
