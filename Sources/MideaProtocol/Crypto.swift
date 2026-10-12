import CommonCrypto
import CryptoKit
import Foundation

/// 协议用到的密码学：HKDF 派生 rootKey、P-256 ECDH 派生 sessionKey、AES-128-CCM 加解密。
enum MideaCrypto {
    struct AuthError: Error, CustomStringConvertible {
        var description: String { "解密校验失败" }
    }

    /// rootKey = HKDF-SHA256(ikm: advertisData, salt: 空, info: "midea_bleapp")，取 16 字节。
    static func rootKey(advertisData: [UInt8]) -> [UInt8] {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: advertisData),
                                         salt: Data(), info: Data("midea_bleapp".utf8),
                                         outputByteCount: 16)
        return key.withUnsafeBytes { Array($0) }
    }

    /// sessionKey = SHA-256(ECDH 共享点 X 坐标) 前 16 字节；公钥为 64 字节 X‖Y。
    static func sessionKey(privateKey: P256.KeyAgreement.PrivateKey, peerPublicKey: [UInt8]) throws -> [UInt8] {
        let peer = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let digest = shared.withUnsafeBytes { SHA256.hash(data: $0) }
        return Array(digest.prefix(16))
    }

    // MARK: - AES-128-CCM（RFC 3610）：8 字节 nonce、8 字节 tag、无附加数据
    // CryptoKit 不提供 CCM，这里用 AES 分组加密自行组合 CBC-MAC + CTR。

    private static let nonceLen = 8, tagLen = 8
    /// 长度字段字节数 L = 15 - nonceLen。
    private static let lenFieldLen = 15 - nonceLen

    /// 输出 nonce ‖ 密文 ‖ tag。nonce 默认随机，测试时可固定。
    static func seal(key: [UInt8], plaintext: [UInt8], nonce: [UInt8]? = nil) -> [UInt8] {
        let nonce = nonce ?? randomBytes(nonceLen)
        let aes = AESBlock(key: key)
        let tag = cbcMac(aes, nonce: nonce, plaintext: plaintext)
        let s0 = aes.encrypt(counterBlock(nonce, 0))
        let cipher = ctr(aes, nonce: nonce, plaintext)
        return nonce + cipher + zip(tag, s0).map { $0 ^ $1 }
    }

    /// 解开 nonce ‖ 密文 ‖ tag，校验失败抛错。
    static func open(key: [UInt8], blob: [UInt8]) throws -> [UInt8] {
        guard blob.count >= nonceLen + tagLen else { throw AuthError() }
        let nonce = Array(blob[..<nonceLen])
        let cipher = Array(blob[nonceLen..<blob.count - tagLen])
        let tag = blob[(blob.count - tagLen)...]
        let aes = AESBlock(key: key)
        let plain = ctr(aes, nonce: nonce, cipher)
        let s0 = aes.encrypt(counterBlock(nonce, 0))
        let expected = zip(cbcMac(aes, nonce: nonce, plaintext: plain), s0).map { $0 ^ $1 }
        guard zip(expected, tag).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0 else { throw AuthError() }
        return plain
    }

    private static func cbcMac(_ aes: AESBlock, nonce: [UInt8], plaintext: [UInt8]) -> [UInt8] {
        // B0 = flags ‖ nonce ‖ 明文长度（L 字节大端）；flags = ((M-2)/2)<<3 | (L-1)
        let flags = UInt8(((tagLen - 2) / 2) << 3 | (lenFieldLen - 1))
        var b0 = [flags] + nonce
        b0 += (0..<lenFieldLen).reversed().map { UInt8(truncatingIfNeeded: plaintext.count >> (8 * $0)) }
        var x = aes.encrypt(b0)
        for start in stride(from: 0, to: plaintext.count, by: 16) {
            var block = Array(plaintext[start..<min(start + 16, plaintext.count)])
            block += [UInt8](repeating: 0, count: 16 - block.count)
            x = aes.encrypt(zip(x, block).map { $0 ^ $1 })
        }
        return Array(x.prefix(tagLen))
    }

    /// 计数器从 1 开始的 CTR；加解密同一运算。
    private static func ctr(_ aes: AESBlock, nonce: [UInt8], _ input: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(input.count)
        for (i, start) in stride(from: 0, to: input.count, by: 16).enumerated() {
            let stream = aes.encrypt(counterBlock(nonce, i + 1))
            out += zip(input[start..<min(start + 16, input.count)], stream).map { $0 ^ $1 }
        }
        return out
    }

    /// A_i = (L-1) ‖ nonce ‖ i（L 字节大端）。
    private static func counterBlock(_ nonce: [UInt8], _ i: Int) -> [UInt8] {
        [UInt8(lenFieldLen - 1)] + nonce + (0..<lenFieldLen).reversed().map { UInt8(truncatingIfNeeded: i >> (8 * $0)) }
    }

    static func randomBytes(_ n: Int) -> [UInt8] {
        var g = SystemRandomNumberGenerator()
        return (0..<n).map { _ in UInt8.random(in: .min ... .max, using: &g) }
    }
}

/// 单个 AES-128 分组加密（ECB、无填充）。
private struct AESBlock {
    let key: [UInt8]

    func encrypt(_ block: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, block, 16, &out, 16, &moved)
        precondition(status == kCCSuccess && moved == 16, "AES 分组加密失败: \(status)")
        return out
    }
}
