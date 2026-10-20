// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DriveManager",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DriveCore", targets: ["DriveCore"]),
        .executable(name: "drive-scan", targets: ["drive-scan"]),
    ],
    targets: [
        .target(name: "DriveCore"),
        .executableTarget(name: "drive-scan", dependencies: ["DriveCore"]),
        .testTarget(name: "DriveCoreTests", dependencies: ["DriveCore"]),
    ]
)
