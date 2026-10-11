// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MideaBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MideaBar", path: "Sources/MideaBar"),
    ]
)
