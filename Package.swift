// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZiproBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZiproKit", targets: ["ZiproKit"]),
        .executable(name: "ZiproBar", targets: ["ZiproBar"]),
    ],
    targets: [
        .target(name: "ZiproKit"),
        .executableTarget(name: "ZiproBar", dependencies: ["ZiproKit"]),
        .testTarget(name: "ZiproKitTests", dependencies: ["ZiproKit"]),
    ]
)
