// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
let appTargets: [Target] = [
    .executableTarget(
        name: "Goldodict",
        dependencies: ["GoldodictCore"],
        path: "Sources/Goldodict",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]
#else
// La cible AppKit n'existe pas sous Linux : le Cloud Agent et la CI y
// n'exercent que GoldodictCore, testable sans micro ni autorisation.
let appTargets: [Target] = []
#endif

let package = Package(
    name: "Goldodict",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "GoldodictCore",
            path: "Sources/GoldodictCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ] + appTargets + [
        .testTarget(
            name: "GoldodictCoreTests",
            dependencies: ["GoldodictCore"],
            path: "Tests/GoldodictCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
