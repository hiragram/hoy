// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "hoy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "hoy", targets: ["hoy"]),
        .library(name: "HoyCore", targets: ["HoyCore"]),
        .library(name: "HoyProtocol", targets: ["HoyProtocol"]),
        .library(name: "HoyDaemon", targets: ["HoyDaemon"]),
        .library(name: "HoyCLI", targets: ["HoyCLI"]),
        .library(name: "HoyMCP", targets: ["HoyMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
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
            dependencies: [
                "HoyProtocol",
                "HoyDaemon",
                "HoyCore",
                "HoyMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "HoyMCP",
            dependencies: ["HoyProtocol"]
        ),
        .executableTarget(
            name: "hoy",
            dependencies: ["HoyCLI"]
        ),
        .testTarget(name: "HoyCoreTests", dependencies: ["HoyCore"]),
        .testTarget(name: "HoyProtocolTests", dependencies: ["HoyProtocol"]),
        .testTarget(name: "HoyDaemonTests", dependencies: ["HoyDaemon"]),
        .testTarget(name: "HoyCLITests", dependencies: ["HoyCLI"]),
        .testTarget(name: "HoyMCPTests", dependencies: ["HoyMCP"]),
    ]
)
