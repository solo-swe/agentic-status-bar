// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgenticStatusBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ASBCore", targets: ["ASBCore"]),
        .executable(name: "asb", targets: ["asb"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Foundation only: no AppKit or SwiftUI, so the core stays portable
        // (see doc/design/future-architecture.md).
        .target(name: "ASBCore"),
        .executableTarget(
            name: "asb",
            dependencies: [
                "ASBCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Under the existing lowercase tests/ folder (macOS paths ignore case, git doesn't).
        .testTarget(name: "ASBCoreTests", dependencies: ["ASBCore"], path: "tests/ASBCoreTests"),
    ]
)
