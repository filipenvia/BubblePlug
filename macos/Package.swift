// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "PlugSpot",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PlugSpotCore", targets: ["PlugSpotCore"]),
        .executable(name: "PlugSpot", targets: ["PlugSpotApp"]),
    ],
    targets: [
        .target(name: "PlugSpotCore"),
        .executableTarget(name: "PlugSpotApp", dependencies: ["PlugSpotCore"], resources: [.process("Resources")]),
    ]
)
