// swift-tools-version: 6.2
// SwiftProjectKit - Centralized Swift project tooling for g-cqd

import PackageDescription

let package = Package(
    name: "SwiftProjectKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        // Core library with configurations and templates
        .library(
            name: "SwiftProjectKitCore",
            targets: ["SwiftProjectKitCore"]
        ),

        // CLI tool for scaffolding and management
        .executable(
            name: "spk",
            targets: ["SwiftProjectKitCLI"]
        ),

        // SwiftLint build plugin (runs on every build with Xcode reporting)
        .plugin(
            name: "SwiftLintBuildPlugin",
            targets: ["SwiftLintBuildPlugin"]
        ),

        // SwiftFormat build plugin (runs on every build in lint-only mode)
        .plugin(
            name: "SwiftFormatBuildPlugin",
            targets: ["SwiftFormatBuildPlugin"]
        ),

        // SwiftLint command plugin (on-demand via `swift package lint`)
        .plugin(
            name: "SwiftLintCommandPlugin",
            targets: ["SwiftLintCommandPlugin"]
        ),

        // SwiftFormat command plugin (on-demand via `swift package format-source-code`)
        .plugin(
            name: "SwiftFormatCommandPlugin",
            targets: ["SwiftFormatCommandPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        // MARK: - Core Library

        .target(
            name: "SwiftProjectKitCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - CLI Tool

        .executableTarget(
            name: "SwiftProjectKitCLI",
            dependencies: [
                "SwiftProjectKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - Build Plugins

        .plugin(
            name: "SwiftLintBuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        .plugin(
            name: "SwiftFormatBuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        // MARK: - Command Plugins

        .plugin(
            name: "SwiftLintCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "lint",
                    description: "Run SwiftLint on Swift source files"
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(ports: [443]),
                        reason: "Download SwiftLint binary from GitHub releases"
                    ),
                ]
            ),
            dependencies: []
        ),

        .plugin(
            name: "SwiftFormatCommandPlugin",
            capability: .command(
                intent: .sourceCodeFormatting,
                permissions: [
                    .writeToPackageDirectory(reason: "Format Swift source files in place"),
                    .allowNetworkConnections(
                        scope: .all(ports: [443]),
                        reason: "Download SwiftFormat binary from GitHub releases"
                    ),
                ]
            ),
            dependencies: []
        ),

        // MARK: - Tests

        .testTarget(
            name: "SwiftProjectKitCoreTests",
            dependencies: ["SwiftProjectKitCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
