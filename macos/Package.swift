// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "BubblePlug",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BubblePlugCore", targets: ["BubblePlugCore"]),
        .executable(name: "BubblePlug", targets: ["BubblePlugApp"]),
    ],
    targets: [
        .target(name: "BubblePlugCore"),
        .executableTarget(name: "BubblePlugApp", dependencies: ["BubblePlugCore"], resources: [.process("Resources")]),
    ]
)
