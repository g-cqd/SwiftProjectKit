// swiftlint:disable no_print_statements
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

        try createProjectStructure(at: outputURL)
        try createConfigurationFiles(at: outputURL)

        print("\nProject '\(name)' created successfully!")
        print("\nNext steps:")
        print("  cd \(name)")
        print("  swift build")
        print("  swift test")
    }

    // MARK: Private

    private func createProjectStructure(at outputURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        if type == .package {
            try generatePackageSwift(name: name).write(
                to: outputURL.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8,
            )
        }

        let sourcesDir = outputURL.appendingPathComponent("Sources/\(name)")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try generateMainFile().write(
            to: sourcesDir.appendingPathComponent("\(name).swift"),
            atomically: true,
            encoding: .utf8,
        )

        let testsDir = outputURL.appendingPathComponent("Tests/\(name)Tests")
        try fm.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try generateTestFile().write(
            to: testsDir.appendingPathComponent("\(name)Tests.swift"),
            atomically: true,
            encoding: .utf8,
        )
    }

    // swiftlint:disable:next function_body_length
    private func createConfigurationFiles(at outputURL: URL) throws {
        let fm = FileManager.default

        if !noSwiftlint {
            try generateSwiftLintConfig().write(
                to: outputURL.appendingPathComponent(".swiftlint.yml"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created .swiftlint.yml")
        }

        if !noSwiftformat {
            try generateSwiftFormatConfig().write(
                to: outputURL.appendingPathComponent(".swiftformat"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created .swiftformat")
        }

        if !noWorkflows {
            let workflowsDir = outputURL.appendingPathComponent(".github/workflows")
            try fm.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
            try generateCIWorkflow(name: name, platforms: .applePlatforms).write(
                to: workflowsDir.appendingPathComponent("ci.yml"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created .github/workflows/ci.yml")
        }

        if !noClaude {
            try generateClaudeMd().write(
                to: outputURL.appendingPathComponent("CLAUDE.md"),
                atomically: true,
                encoding: .utf8,
            )
            print("  Created CLAUDE.md")
        }

        try generateReadme(name: name).write(
            to: outputURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8,
        )
        print("  Created README.md")

        try generateGitignore().write(
            to: outputURL.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8,
        )
        print("  Created .gitignore")
    }

    private func generateMainFile() -> String {
        """
        // \(name)
        // Created with SwiftProjectKit

        import Foundation

        public struct \(name) {
            public init() {}
        }
        """
    }

    private func generateTestFile() -> String {
        """
        import Testing
        @testable import \(name)

        @Test func example() {
            let instance = \(name)()
            #expect(true)
        }
        """
    }

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
