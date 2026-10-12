// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MideaBar",
    platforms: [.macOS(.v14)],
    targets: [
        // 美的空调 BLE 协议：帧、加密、握手、家电帧。纯算法，不依赖蓝牙，可离线测试。
        .target(name: "MideaProtocol", path: "Sources/MideaProtocol"),
        .executableTarget(name: "MideaBar", dependencies: ["MideaProtocol"], path: "Sources/MideaBar"),
        .testTarget(name: "MideaProtocolTests", dependencies: ["MideaProtocol"], path: "Tests/MideaProtocolTests"),
    ]
)
