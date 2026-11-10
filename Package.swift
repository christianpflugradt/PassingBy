// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PassingBy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PassingByApp", targets: ["PassingByApp"]),
        .executable(name: "PassingByTests", targets: ["PassingByTests"]),
    ],
    targets: [
        .target(name: "PassingByCore"),
        .executableTarget(name: "PassingByApp", dependencies: ["PassingByCore"]),
        .executableTarget(name: "PassingByTests", dependencies: ["PassingByCore"], resources: [.copy("Fixtures")]),
    ]
)
