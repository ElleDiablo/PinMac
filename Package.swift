// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PinMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PinMac", path: "Sources/PinMac")
    ]
)
