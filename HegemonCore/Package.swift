// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HegemonCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HegemonCore", targets: ["HegemonCore"]),
        .executable(name: "hegemon-sim", targets: ["hegemon-sim"]),
    ],
    targets: [
        .target(
            name: "HegemonCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "hegemon-sim",
            dependencies: ["HegemonCore"]
        ),
        .testTarget(
            name: "HegemonCoreTests",
            dependencies: ["HegemonCore"]
        ),
    ]
)
