// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    .target(
        name: "GoldodictCore",
        path: "Sources/GoldodictCore",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
        name: "GoldodictCoreTests",
        dependencies: ["GoldodictCore"],
        path: "Tests/GoldodictCoreTests",
        swiftSettings: [.swiftLanguageMode(.v5)]
    ),
]

// La cible applicative dépend d'AppKit, Speech et SwiftUI : elle n'existe que
// sur macOS. Sur les autres plateformes (Linux CI), seule la logique pure de
// GoldodictCore est compilée et testée.
#if os(macOS)
targets.append(
    .executableTarget(
        name: "Goldodict",
        dependencies: ["GoldodictCore"],
        path: "Sources/Goldodict",
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
)
#endif

let package = Package(
    name: "Goldodict",
    platforms: [.macOS("26.0")],
    targets: targets
)
