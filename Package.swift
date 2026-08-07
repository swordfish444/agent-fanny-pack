// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentFannyPack",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AgentFannyPackCore", targets: ["AgentFannyPackCore"]),
        .executable(name: "AgentFannyPack", targets: ["AgentFannyPack"]),
        .executable(name: "AgentFannyPackTests", targets: ["AgentFannyPackTests"])
    ],
    targets: [
        .target(name: "AgentFannyPackCore"),
        .executableTarget(
            name: "AgentFannyPack",
            dependencies: ["AgentFannyPackCore"]
        ),
        .executableTarget(name: "AgentFannyPackTests", dependencies: ["AgentFannyPackCore"])
    ]
)
