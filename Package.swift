// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hoy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HoyCore", targets: ["HoyCore"]),
        .library(name: "HoyProtocol", targets: ["HoyProtocol"]),
        .library(name: "HoyDaemon", targets: ["HoyDaemon"]),
        .library(name: "HoyCLI", targets: ["HoyCLI"]),
        .library(name: "HoyMCP", targets: ["HoyMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        .target(
            name: "HoyCore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .target(name: "HoyProtocol"),
        .target(
            name: "HoyDaemon",
            dependencies: ["HoyCore", "HoyProtocol"]
        ),
        .target(
            name: "HoyCLI",
            dependencies: ["HoyProtocol"]
        ),
        .target(
            name: "HoyMCP",
            dependencies: ["HoyProtocol"]
        ),
        .testTarget(name: "HoyCoreTests", dependencies: ["HoyCore"]),
        .testTarget(name: "HoyProtocolTests", dependencies: ["HoyProtocol"]),
        .testTarget(name: "HoyDaemonTests", dependencies: ["HoyDaemon"]),
        .testTarget(name: "HoyCLITests", dependencies: ["HoyCLI"]),
        .testTarget(name: "HoyMCPTests", dependencies: ["HoyMCP"]),
    ]
)
