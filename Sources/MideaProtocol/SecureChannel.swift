import CryptoKit

/// 一条连接上的加密通道：构造握手 / 业务出包、解析入包。只管字节，不管时序与重发。
///
/// 握手：c1(openId6) → c2(取设备临时公钥) → c3(我方公钥 + sessionKey 加密的 advertisData)，
/// c1~c3 用 rootKey 加密，此后业务帧（c4）用 sessionKey 加密。
public final class SecureChannel {
    /// 解析后的入包。
    public enum Inbound: Equatable {
        case c1(result: UInt8)
        case c2(peerPublicKey: [UInt8])
        case c3(result: UInt8)
        /// 业务回包，内容为美的家电帧（0xAA 开头）。
        case biz([UInt8])
        /// 设备返回的短错误帧（如 ff04 安全层失败、ff05 计数错误）。
        case securityError([UInt8])
        /// 解不开或格式不对的帧。
        case malformed(String)
        case unknown
    }

    private let advertisData: [UInt8]
    private let openID: [UInt8]
    private let rootKey: [UInt8]
    private var sessionKey: [UInt8]?
    private var privateKey: P256.KeyAgreement.PrivateKey?
    private var connSeq = SecureChannel.randomSeq()
    private var secSeq = SecureChannel.randomSeq()
    private var rxBuffer: [UInt8] = []

    public var isEstablished: Bool { sessionKey != nil }

    /// - Parameters:
    ///   - advertisData: 由广播重建的 15 字节设备标识（见 `Advertisement`）。
    ///   - openID: 6 字节会话 ID，默认随机。
    public init(advertisData: [UInt8], openID: [UInt8]? = nil) {
        self.advertisData = advertisData
        self.openID = openID ?? MideaCrypto.randomBytes(6)
        rootKey = MideaCrypto.rootKey(advertisData: advertisData)
    }

    /// c1：每次调用都是新帧（新序号、新 nonce）；设备常忽略新连接的前一两个 c1，需要反复发。
    public func makeC1() -> [UInt8] { wrap(.c1, body: openID, key: rootKey, as: .t2) }

    /// c2：设备每收到一个 c2 就轮换临时密钥，重发时必须发同一帧，不要再次调用。
    public func makeC2() -> [UInt8] { wrap(.c2, body: [], key: rootKey, as: .t2) }

    /// 收到设备公钥后生成我方密钥对并派生 sessionKey。
    public func acceptPeerKey(_ peerPublicKey: [UInt8]) throws {
        let key = P256.KeyAgreement.PrivateKey()
        sessionKey = try MideaCrypto.sessionKey(privateKey: key, peerPublicKey: peerPublicKey)
        privateKey = key
    }

    /// c3：我方公钥 ‖ sessionKey 加密的 advertisData，供设备核对双方密钥一致。
    public func makeC3() -> [UInt8] {
        guard let sessionKey, let privateKey else { preconditionFailure("需先 acceptPeerKey") }
        let body = Array(privateKey.publicKey.rawRepresentation)
            + MideaCrypto.seal(key: sessionKey, plaintext: advertisData)
        return wrap(.c3, body: body, key: rootKey, as: .t2)
    }

    /// 业务帧：家电帧外包业务层（type 0x20），再用 sessionKey 加密。每次调用序号递增。
    public func makeBiz(_ appliance: [UInt8]) -> [UInt8] {
        guard let sessionKey else { preconditionFailure("需先完成握手") }
        return wrap(.c4, body: Frames.encodeBiz(type: 0x20, body: appliance), key: sessionKey, as: .t3)
    }

    /// 喂入一段收到的字节（蓝牙通知可能分片或粘包），返回其中完整帧的解析结果。
    public func feed(_ chunk: [UInt8]) -> [Inbound] {
        rxBuffer += chunk
        return Frames.extractConnFrames(&rxBuffer).map { frame in
            do { return try receive(frame) } catch { return .malformed(String(describing: error)) }
        }
    }

    /// 解析一个完整的连接层帧。
    func receive(_ frame: [UInt8]) throws -> Inbound {
        let (type, body, _) = try Frames.decodeConn(frame)
        let key: [UInt8]
        switch type {
        case Frames.ConnType.t2.rawValue: key = rootKey
        case Frames.ConnType.t3.rawValue:
            guard let sessionKey else { return .unknown }
            key = sessionKey
        default: return .unknown
        }
        // 密文至少有 8 字节 nonce + 8 字节 tag，更短的是设备的错误码
        if body.count < 16 { return .securityError(body) }
        let (cmd, payload) = try Frames.decodeSecurity(try MideaCrypto.open(key: key, blob: body))
        switch cmd {
        case Frames.SecCmd.c1.rawValue: return .c1(result: payload.first ?? 0)
        case Frames.SecCmd.c2.rawValue: return .c2(peerPublicKey: payload)
        case Frames.SecCmd.c3.rawValue: return .c3(result: payload.first ?? 0)
        case Frames.SecCmd.c4.rawValue: return .biz(try Frames.decodeBiz(payload))
        default: return .unknown
        }
    }

    private func wrap(_ cmd: Frames.SecCmd, body: [UInt8], key: [UInt8], as type: Frames.ConnType) -> [UInt8] {
        let sec = Frames.encodeSecurity(cmd, body: body, seq: Self.next(&secSeq))
        return Frames.encodeConn(type, body: MideaCrypto.seal(key: key, plaintext: sec), seq: Self.next(&connSeq))
    }

    /// 序号 1...255 循环，跳过 0。
    private static func next(_ seq: inout UInt8) -> UInt8 {
        seq = seq == 255 ? 1 : seq + 1
        return seq
    }

    private static func randomSeq() -> UInt8 { .random(in: 1...255) }
}
