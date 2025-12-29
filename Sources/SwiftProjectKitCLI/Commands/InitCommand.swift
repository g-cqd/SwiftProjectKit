import ArgumentParser
import Foundation
import SwiftProjectKitCore

struct InitCommand: AsyncParsableCommand {
    // MARK: Internal

    enum ProjectType: String, ExpressibleByArgument, CaseIterable {
        case package
        case app
    }

    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new Swift project with standard configuration",
    )

    @Option(name: .shortAndLong, help: "Project name")
    var name: String

    @Option(name: .shortAndLong, help: "Project type (package or app)")
    var type: ProjectType = .package

    @Option(name: .long, help: "Output directory (defaults to current)")
    var output: String = "."

    @Flag(name: .long, help: "Skip SwiftLint configuration")
    var noSwiftlint = false

    @Flag(name: .long, help: "Skip SwiftFormat configuration")
    var noSwiftformat = false

    @Flag(name: .long, help: "Skip GitHub workflows")
    var noWorkflows = false

    @Flag(name: .long, help: "Skip CLAUDE.md")
    var noClaude = false

    func run() async throws {
        let outputURL = URL(fileURLWithPath: output).appendingPathComponent(name)

        print("Creating \(type.rawValue) '\(name)' at \(outputURL.path)...")

        let fm = FileManager.default
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Create Package.swift
        if type == .package {
            let packageSwift = generatePackageSwift(name: name)
            try packageSwift.write(
                to: outputURL.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8,
            )
        }

        // Create source directory
        let sourcesDir = outputURL.appendingPathComponent("Sources/\(name)")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // Create main file
        let mainFile = """
        // \(name)
        // Created with SwiftProjectKit

        import Foundation

        public struct \(name) {
            public init() {}
        }
        """
        try mainFile.write(
            to: sourcesDir.appendingPathComponent("\(name).swift"),
            atomically: true,
            encoding: .utf8,
        )

        // Create tests directory
        let testsDir = outputURL.appendingPathComponent("Tests/\(name)Tests")
        try fm.createDirectory(at: testsDir, withIntermediateDirectories: true)

        let testFile = """
        import Testing
        @testable import \(name)

        @Test func example() {
            let instance = \(name)()
            #expect(true)
        }
        """
        try testFile.write(
            to: testsDir.appendingPathComponent("\(name)Tests.swift"),
            atomically: true,
            encoding: .utf8,
        )

        // SwiftLint config
        if !noSwiftlint {
            let swiftlintConfig = generateSwiftLintConfig()
            try swiftlintConfig.write(
                to: outputURL.appendingPathComponent(".swiftlint.yml"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created .swiftlint.yml")
        }

        // SwiftFormat config
        if !noSwiftformat {
            let swiftformatConfig = generateSwiftFormatConfig()
            try swiftformatConfig.write(
                to: outputURL.appendingPathComponent(".swiftformat"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created .swiftformat")
        }

        // GitHub workflows
        if !noWorkflows {
            let workflowsDir = outputURL.appendingPathComponent(".github/workflows")
            try fm.createDirectory(at: workflowsDir, withIntermediateDirectories: true)

            let ciWorkflow = generateCIWorkflow(name: name, platforms: .applePlatforms)
            try ciWorkflow.write(
                to: workflowsDir.appendingPathComponent("ci.yml"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created .github/workflows/ci.yml")
        }

        // CLAUDE.md
        if !noClaude {
            let claudeMd = generateClaudeMd()
            try claudeMd.write(
                to: outputURL.appendingPathComponent("CLAUDE.md"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created CLAUDE.md")
        }

        // README.md
        let readme = generateReadme(name: name)
        try readme.write(
            to: outputURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8,
        )
        print("  Created README.md")

        // .gitignore
        let gitignore = generateGitignore()
        try gitignore.write(
            to: outputURL.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8,
        )
        print("  Created .gitignore")

        print("\nProject '\(name)' created successfully!")
        print("\nNext steps:")
        print("  cd \(name)")
        print("  swift build")
        print("  swift test")
    }

    // MARK: Private

    // MARK: - Generators

    private func generatePackageSwift(name: String) -> String {
        """
        // swift-tools-version: \(defaultSwiftVersion)

        import PackageDescription

        let package = Package(
            name: "\(name)",
            platforms: [
                .iOS(.v18),
                .macOS(.v15),
            ],
            products: [
                .library(
                    name: "\(name)",
                    targets: ["\(name)"]
                ),
            ],
            dependencies: [
                .package(url: "https://github.com/g-cqd/SwiftProjectKit.git", from: "1.0.0"),
            ],
            targets: [
                .target(
                    name: "\(name)",
                    dependencies: [],
                    plugins: [
                        .plugin(name: "SwiftLintBuildPlugin", package: "SwiftProjectKit"),
                    ]
                ),
                .testTarget(
                    name: "\(name)Tests",
                    dependencies: ["\(name)"]
                ),
            ]
        )
        """
    }

    private func generateSwiftLintConfig() -> String {
        DefaultConfigs.swiftlint
    }

    private func generateSwiftFormatConfig() -> String {
        DefaultConfigs.swiftformat
    }

    private func generateCIWorkflow(name: String, platforms: PlatformConfiguration) -> String {
        DefaultConfigs.ciWorkflow(name: name, platforms: platforms)
    }

    private func generateClaudeMd() -> String {
        DefaultConfigs.claudeMd
    }

    private func generateReadme(name: String) -> String {
        """
        # \(name)

        A Swift package created with [SwiftProjectKit](https://github.com/g-cqd/SwiftProjectKit).

        ## Installation

        Add to your `Package.swift`:

        ```swift
        dependencies: [
            .package(url: "https://github.com/g-cqd/\(name).git", from: "1.0.0"),
        ]
        ```

        ## Usage

        ```swift
        import \(name)

        let instance = \(name)()
        ```

        ## License

        MIT
        """
    }

    private func generateGitignore() -> String {
        """
        # Xcode
        .DS_Store
        *.xcodeproj/
        *.xcworkspace/
        xcuserdata/
        DerivedData/

        # Swift Package Manager
        .build/
        .swiftpm/
        Package.resolved

        # Secrets
        .env
        *.pem
        credentials.json
        """
    }
}
