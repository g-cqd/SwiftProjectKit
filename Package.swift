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
        .visionOS(.v2),
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

        // SwiftFormat build plugin (runs on every build in lint-only mode)
        .plugin(
            name: "SwiftFormatBuildPlugin",
            targets: ["SwiftFormatBuildPlugin"]
        ),

        // SwiftFormat command plugin (on-demand via `swift package format-source-code`)
        .plugin(
            name: "SwiftFormatCommandPlugin",
            targets: ["SwiftFormatCommandPlugin"]
        ),

        // SWA build plugin (runs both unused + duplicates on every build)
        .plugin(
            name: "SWABuildPlugin",
            targets: ["SWABuildPlugin"]
        ),

        // SWA command plugin (on-demand via `swift package swa`)
        .plugin(
            name: "SWACommandPlugin",
            targets: ["SWACommandPlugin"]
        ),

        // Unused code build plugin (runs unused detection on every build)
        .plugin(
            name: "UnusedCodeBuildPlugin",
            targets: ["UnusedCodeBuildPlugin"]
        ),

        // Duplication build plugin (runs duplication detection on every build)
        .plugin(
            name: "DuplicationBuildPlugin",
            targets: ["DuplicationBuildPlugin"]
        ),

        // Unused code command plugin (on-demand via `swift package unused`)
        .plugin(
            name: "UnusedCodeCommandPlugin",
            targets: ["UnusedCodeCommandPlugin"]
        ),

        // Duplication command plugin (on-demand via `swift package duplicates`)
        .plugin(
            name: "DuplicationCommandPlugin",
            targets: ["DuplicationCommandPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
    ],
    targets: [
        // MARK: - Core Library

        .target(
            name: "SwiftProjectKitCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
                .enableExperimentalFeature("MemberImportVisibility"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildPlugin"),
                .plugin(name: "UnusedCodeBuildPlugin"),
                .plugin(name: "DuplicationBuildPlugin"),
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
                .enableExperimentalFeature("MemberImportVisibility"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildPlugin"),
                .plugin(name: "UnusedCodeBuildPlugin"),
                .plugin(name: "DuplicationBuildPlugin"),
            ]
        ),

        // MARK: - Build Plugins

        .plugin(
            name: "SwiftFormatBuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        // MARK: - Command Plugins

        .plugin(
            name: "SwiftFormatCommandPlugin",
            capability: .command(
                intent: .sourceCodeFormatting,
                permissions: [
                    .writeToPackageDirectory(reason: "Format Swift source files in place")
                ]
            ),
            dependencies: []
        ),

        // MARK: - SWA Plugins (Static Analysis)

        .plugin(
            name: "SWABuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        .plugin(
            name: "SWACommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "swa",
                    description: "Run static analysis (unused code, duplicates) on Swift source files"
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(ports: [443]),
                        reason: "Download SwiftStaticAnalysis binary from GitHub releases"
                    )
                ]
            ),
            dependencies: []
        ),

        // Unused code plugins
        .plugin(
            name: "UnusedCodeBuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        .plugin(
            name: "UnusedCodeCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "unused",
                    description: "Detect unused code in Swift source files"
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(ports: [443]),
                        reason: "Download SwiftStaticAnalysis binary from GitHub releases"
                    )
                ]
            ),
            dependencies: []
        ),

        // Duplication plugins
        .plugin(
            name: "DuplicationBuildPlugin",
            capability: .buildTool(),
            dependencies: []
        ),

        .plugin(
            name: "DuplicationCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "duplicates",
                    description: "Detect code duplication in Swift source files"
                ),
                permissions: [
                    .allowNetworkConnections(
                        scope: .all(ports: [443]),
                        reason: "Download SwiftStaticAnalysis binary from GitHub releases"
                    )
                ]
            ),
            dependencies: []
        ),

        // MARK: - Tests

        .testTarget(
            name: "SwiftProjectKitCoreTests",
            dependencies: [
                "SwiftProjectKitCore",
                .product(name: "Yams", package: "Yams"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
                .enableExperimentalFeature("MemberImportVisibility"),
            ],
            plugins: [
                .plugin(name: "SwiftFormatBuildPlugin"),
                .plugin(name: "UnusedCodeBuildPlugin"),
                .plugin(name: "DuplicationBuildPlugin"),
            ]
        ),
    ]
)
