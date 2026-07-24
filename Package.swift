// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Abracadabra",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "AbracadabraCore",
            path: "Sources/AbracadabraCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Abracadabra",
            dependencies: ["AbracadabraCore"],
            path: "Sources/Abracadabra",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AbracadabraCoreTests",
            dependencies: ["AbracadabraCore"],
            path: "Tests/AbracadabraCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
