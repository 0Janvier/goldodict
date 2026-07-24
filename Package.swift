// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Goldodict",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "GoldodictCore",
            path: "Sources/GoldodictCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Goldodict",
            dependencies: ["GoldodictCore"],
            path: "Sources/Goldodict",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GoldodictCoreTests",
            dependencies: ["GoldodictCore"],
            path: "Tests/GoldodictCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
