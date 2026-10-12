import CryptoKit
@testable import MideaProtocol
import XCTest

/// 一致性向量取自参考实现 midea-ble-go（AES-CCM 另经 Python cryptography 交叉验证）。
final class MideaProtocolTests: XCTestCase {
    func testRootKey() {
        XCTAssertEqual(hex(MideaCrypto.rootKey(advertisData: bytes("ac3132333435363738aabbccddeeff"))),
                       "3ab82c346a77b6593d5ebe9f25d3cf50")
    }

    func testAESCCMVectors() throws {
        let key = bytes("000102030405060708090a0b0c0d0e0f"), nonce = bytes("1011121314151617")
        let vectors = [
            ("", "299102acd1e90cea"),
            ("68656c6c6f", "78010a07da2c9be4808c5eca88"),
            ("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021",
             "10656468b111928e438be2206363113c1b9e91131daff748ec81d6115cb0b34f32ecb6e6447288393c61"),
        ]
        for (plain, sealed) in vectors {
            let blob = MideaCrypto.seal(key: key, plaintext: bytes(plain), nonce: nonce)
            XCTAssertEqual(hex(blob), hex(nonce) + sealed)
            XCTAssertEqual(hex(try MideaCrypto.open(key: key, blob: blob)), plain)
        }
    }

    func testAESCCMRejectsTampering() {
        let key = [UInt8](repeating: 7, count: 16)
        var blob = MideaCrypto.seal(key: key, plaintext: Array("hello midea".utf8))
        blob[10] ^= 1
        XCTAssertThrowsError(try MideaCrypto.open(key: key, blob: blob))
    }

    func testECDHAgrees() throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        XCTAssertEqual(try MideaCrypto.sessionKey(privateKey: a, peerPublicKey: Array(b.publicKey.rawRepresentation)),
                       try MideaCrypto.sessionKey(privateKey: b, peerPublicKey: Array(a.publicKey.rawRepresentation)))
    }

    func testFrames() throws {
        XCTAssertEqual(hex(Frames.encodeConn(.t2, body: [1, 2, 3, 0xFE], seq: 9)), "aa55080902010203fee9")
        XCTAssertEqual(hex(Frames.encodeSecurity(.c3, body: [9, 8], seq: 200)), "03c8020908")
        XCTAssertEqual(hex(Frames.encodeBiz(type: 0x20, body: [0xAA, 1, 2])), "200700aa01022c")
        let conn = try Frames.decodeConn(bytes("aa55080902010203fee9"))
        XCTAssertEqual(conn.type, 2)
        XCTAssertEqual(conn.seq, 9)
        XCTAssertEqual(conn.body, [1, 2, 3, 0xFE])
    }

    func testExtractFramesAcrossFragments() {
        var buf = bytes("0000aa5508090201")
        XCTAssertTrue(Frames.extractConnFrames(&buf).isEmpty)
        buf += bytes("0203fee9aa")
        XCTAssertEqual(Frames.extractConnFrames(&buf).map(hex), ["aa55080902010203fee9"])
        XCTAssertEqual(buf, [0xAA])
        buf += bytes("55080902010203fee9")
        XCTAssertEqual(Frames.extractConnFrames(&buf).count, 1)
        XCTAssertTrue(buf.isEmpty)
    }

    func testAdvertisement() {
        // 厂商 ID A8 06 + payload [01][SN14][01 03 00 32][MAC6][00]
        let data = bytes("a806" + "01" + hex(Array("12345678AC0001".utf8)) + "01030032" + "ffeeddccbbaa" + "00")
        let ad = Advertisement(manufacturerData: data)
        XCTAssertEqual(ad?.sn, "12345678AC0001")
        XCTAssertEqual(ad.map { hex($0.advertisData) }, "ac3132333435363738aabbccddeeff")
        XCTAssertNil(Advertisement(manufacturerData: Array(data.prefix(20))), "不完整的广播包不能解析")
    }

    func testQueryFrame() {
        XCTAssertEqual(hex(Appliance.queryFrame(order: 7)), "aa17ac00000000000003412100ff03ff000200000007745a")
    }

    func testControlFrames() {
        var s = ACState()
        s.power = true
        s.mode = ACMode.heat.rawValue
        s.apply(.temperature(24.5))
        s.fanSpeed = FanSpeed.mid.rawValue
        s.swingUpDown = true
        s.eco = true
        s.beep = false
        XCTAssertEqual(hex(Appliance.controlFrame(s, order: 5)),
                       "aa24ac000000000002024003983c7f7fff3c0080009999999999000a0c8000000000053c88")

        var s2 = ACState()
        s2.apply(.temperature(30))
        s2.apply(.strong(true))
        s2.swingLeftRight = true
        XCTAssertEqual(hex(Appliance.controlFrame(s2, order: 255)),
                       "aa24ac0000000000020240424e667f7fff332000009999999999000a128000000000ff040a")
    }

    func testParseStatus() {
        let frame = bytes("aa22ac00000000000003c00159500000003c20100066710d0003000000000000000072")
        var expected = ACStatus()
        expected.power = true
        expected.mode = ACMode.cool.rawValue
        expected.temperature = 25.5
        expected.fanSpeed = 80
        expected.swingUpDown = true
        expected.eco = true
        expected.strong = true
        expected.temperature2 = 25.5
        expected.indoor = 26.3
        expected.outdoor = 31.5
        XCTAssertEqual(Appliance.parseStatus(frame), expected)

        // 外机停机时室外温度原始值为 0xFF，应视为无读数
        var noOutdoor = frame
        noOutdoor[22] = 0xFF
        noOutdoor[noOutdoor.count - 1] = Frames.negSum(noOutdoor[1..<(noOutdoor.count - 1)])
        XCTAssertNil(Appliance.parseStatus(noOutdoor)?.outdoor)
        XCTAssertEqual(Appliance.parseStatus(noOutdoor)?.indoor, 26.3)

        var corrupted = frame
        corrupted[13] ^= 1
        XCTAssertNil(Appliance.parseStatus(corrupted), "校验和不对应拒绝")
    }

    /// 模拟设备走完握手：验证双方用同一 rootKey / sessionKey 能互相解密。
    func testHandshakeAgainstSimulatedDevice() throws {
        let ad = bytes("ac3132333435363738aabbccddeeff")
        let root = MideaCrypto.rootKey(advertisData: ad)
        let app = SecureChannel(advertisData: ad)

        // 设备解开 c1
        let c1 = try Frames.decodeConn(app.makeC1())
        XCTAssertEqual(c1.type, 2)
        XCTAssertEqual(try Frames.decodeSecurity(try MideaCrypto.open(key: root, blob: c1.body)).cmd, 1)

        // 设备回 c2：附上临时公钥
        let device = P256.KeyAgreement.PrivateKey()
        let reply = Frames.encodeConn(.t2, body: MideaCrypto.seal(
            key: root, plaintext: Frames.encodeSecurity(.c2, body: Array(device.publicKey.rawRepresentation), seq: 1)), seq: 1)
        guard case .c2(let peer) = try app.receive(reply) else { return XCTFail("应解析为 c2") }
        try app.acceptPeerKey(peer)

        // 设备解开 c3：用我方公钥算出同一个 sessionKey，并能解出 advertisData
        let c3 = try Frames.decodeSecurity(try MideaCrypto.open(key: root, blob: Frames.decodeConn(app.makeC3()).body))
        XCTAssertEqual(c3.cmd, 3)
        let sk = try MideaCrypto.sessionKey(privateKey: device, peerPublicKey: Array(c3.body.prefix(64)))
        XCTAssertEqual(try MideaCrypto.open(key: sk, blob: Array(c3.body.dropFirst(64))), ad)

        // 设备回业务帧，App 能解出家电帧
        let status = bytes("aa22ac00000000000003c00159500000003c20100066710d0003000000000000000072")
        let biz = Frames.encodeConn(.t3, body: MideaCrypto.seal(
            key: sk, plaintext: Frames.encodeSecurity(.c4, body: Frames.encodeBiz(type: 0x20, body: status), seq: 2)), seq: 2)
        XCTAssertEqual(try app.receive(biz), .biz(status))
    }

    private func bytes(_ s: String) -> [UInt8] {
        var out: [UInt8] = [], i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
}
