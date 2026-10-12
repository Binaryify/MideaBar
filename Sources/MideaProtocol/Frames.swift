/// 三层帧编解码。外发顺序：业务帧 → 安全层（加密）→ 连接层 → 蓝牙写入；接收反之。
enum Frames {
    /// 连接层类型：t2 内含 rootKey 加密的握手帧，t3 内含 sessionKey 加密的业务帧。
    enum ConnType: UInt8 { case t1 = 1, t2 = 2, t3 = 3 }
    /// 安全层命令：c1~c3 握手，c4 业务。
    enum SecCmd: UInt8 { case c1 = 1, c2 = 2, c3 = 3, c4 = 4 }

    struct DecodeError: Error, CustomStringConvertible {
        let description: String
    }

    /// 负和校验：-Σ & 0xFF。
    static func negSum<C: Collection<UInt8>>(_ bytes: C) -> UInt8 {
        UInt8(truncatingIfNeeded: -bytes.reduce(0) { $0 + Int($1) })
    }

    // MARK: 连接层  AA 55 LEN SEQ TYPE body CHK（LEN = body + 4，CHK 覆盖 LEN..body）

    static func encodeConn(_ type: ConnType, body: [UInt8], seq: UInt8) -> [UInt8] {
        precondition(body.count + 4 <= 255, "连接层 body 过长")
        var out: [UInt8] = [0xAA, 0x55, UInt8(body.count + 4), seq, type.rawValue] + body
        out.append(negSum(out[2...]))
        return out
    }

    static func decodeConn(_ buf: [UInt8]) throws -> (type: UInt8, body: [UInt8], seq: UInt8) {
        guard buf.count >= 6, buf[0] == 0xAA, buf[1] == 0x55 else {
            throw DecodeError(description: "连接层帧头错误")
        }
        let bodyLen = Int(buf[2]) - 4
        guard bodyLen >= 0, 5 + bodyLen <= buf.count else {
            throw DecodeError(description: "连接层长度错误")
        }
        return (buf[4], Array(buf[5..<5 + bodyLen]), buf[3])
    }

    // MARK: 安全层  CMD SEQ LEN body（无校验，完整性由 AES-CCM 保证）

    static func encodeSecurity(_ cmd: SecCmd, body: [UInt8], seq: UInt8) -> [UInt8] {
        [cmd.rawValue, seq, UInt8(body.count)] + body
    }

    static func decodeSecurity(_ buf: [UInt8]) throws -> (cmd: UInt8, body: [UInt8]) {
        guard buf.count >= 3 else { throw DecodeError(description: "安全层帧过短") }
        let end = min(3 + Int(buf[2]), buf.count)
        return (buf[0], Array(buf[3..<end]))
    }

    // MARK: 业务层  TYPE LEN 00 body CHK（LEN = body + 4，CHK 覆盖 TYPE..body）

    static func encodeBiz(type: UInt8, body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [type, UInt8(body.count + 4), 0] + body
        out.append(negSum(out))
        return out
    }

    static func decodeBiz(_ buf: [UInt8]) throws -> [UInt8] {
        guard buf.count >= 4 else { throw DecodeError(description: "业务层帧过短") }
        return Array(buf[3..<buf.count - 1])
    }

    /// 从接收缓冲里切出完整的连接层帧（通知可能分片或粘包），返回切出的帧并移除已消费字节。
    static func extractConnFrames(_ buffer: inout [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        while true {
            guard let i = buffer.indices.dropLast().first(where: { buffer[$0] == 0xAA && buffer[$0 + 1] == 0x55 }) else {
                // 末尾单个 0xAA 可能是下一片的帧头，留着
                buffer = buffer.last == 0xAA ? [0xAA] : []
                return frames
            }
            buffer.removeFirst(i)
            guard buffer.count >= 3 else { return frames }
            let total = 2 + Int(buffer[2])
            guard buffer.count >= total else { return frames }
            frames.append(Array(buffer[..<total]))
            buffer.removeFirst(total)
        }
    }
}
