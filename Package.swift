// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PajlotAssist",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PajlotAssist",
            path: "Sources/PajlotAssist",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
