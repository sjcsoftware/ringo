// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Ringo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ringo", targets: ["RingoCLI"]),
        .executable(name: "RingoApp", targets: ["RingoApp"]),
        .library(name: "RingoEngine", targets: ["RingoEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Pure model layer: formats, edges, tools, errors, JSON result schema. Foundation only.
        .target(name: "RingoDomain", swiftSettings: v5),
        // Versioned settings shared by GUI and CLI. Foundation only.
        .target(name: "RingoSettings", dependencies: ["RingoDomain"], swiftSettings: v5),
        // Capability registry, planning, jobs, atomic output commit, subprocess runner. Foundation only.
        .target(name: "RingoCore", dependencies: ["RingoDomain", "RingoSettings"], swiftSettings: v5),
        // Apple-framework providers (ImageIO, PDFKit, AVFoundation, CoreText, ModelIO, Vision).
        .target(name: "RingoNative", dependencies: ["RingoCore"], swiftSettings: v5),
        // Optional external tools (FFmpeg, ImageMagick, Pandoc, LibreOffice, ...), discovered lazily.
        .target(name: "RingoExternal", dependencies: ["RingoCore"], swiftSettings: v5),
        // The six file tools plus archive tools.
        .target(name: "RingoTools", dependencies: ["RingoCore", "RingoNative", "RingoExternal"], swiftSettings: v5),
        // Composition root used by every frontend.
        .target(name: "RingoEngine", dependencies: ["RingoCore", "RingoNative", "RingoExternal", "RingoTools"], swiftSettings: v5),
        .executableTarget(
            name: "RingoCLI",
            dependencies: ["RingoEngine", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            swiftSettings: v5
        ),
        // GUI frontend modules.
        .target(name: "RingoFinderBridge", dependencies: ["RingoDomain"], swiftSettings: v5),
        .target(name: "RingoShortcuts", dependencies: ["RingoSettings"], swiftSettings: v5),
        .target(name: "RingoRadialUI", dependencies: ["RingoEngine"], swiftSettings: v5),
        .executableTarget(
            name: "RingoApp",
            dependencies: ["RingoEngine", "RingoRadialUI", "RingoFinderBridge", "RingoShortcuts"],
            swiftSettings: v5
        ),
        .testTarget(
            name: "RingoTests",
            dependencies: ["RingoEngine", "RingoShortcuts", "RingoRadialUI", "RingoFinderBridge"],
            swiftSettings: v5
        ),
    ]
)
