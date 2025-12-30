// swiftlint:disable no_print_statements
import ArgumentParser
import Foundation
import SwiftProjectKitCore

// MARK: - WorkflowCommand

struct WorkflowCommand: AsyncParsableCommand {
    // swa:ignore-unused
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "Manage GitHub Actions workflows",
        subcommands: [
            GenerateWorkflowCommand.self
        ],
        defaultSubcommand: GenerateWorkflowCommand.self,
    )
}

// MARK: - GenerateWorkflowCommand

struct GenerateWorkflowCommand: AsyncParsableCommand {
    // MARK: Internal

    enum WorkflowType: String, ExpressibleByArgument, CaseIterable {
        case ci
        case all
    }

    // swa:ignore-unused
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate GitHub Actions workflow files",
    )

    @Option(name: .shortAndLong, help: "Workflow type to generate (ci includes release)")
    var type: WorkflowType = .ci

    @Option(name: .shortAndLong, help: "Project name (auto-detected from Package.swift)")
    var name: String?

    @Option(name: .shortAndLong, help: "Project path")
    var path: String = "."

    @Flag(name: .long, help: "macOS only (no platform matrix)")
    var macosOnly = false

    @Flag(name: .long, help: "Exclude release jobs from CI workflow")
    var noRelease = false

    @Flag(name: .long, help: "Overwrite existing workflows")
    var force = false

    func run() async throws {
        let projectURL = URL(fileURLWithPath: path)
        let workflowsDir = projectURL.appendingPathComponent(".github/workflows")

        // Detect project name
        var projectName = name ?? projectURL.lastPathComponent
        let packageSwiftPath = projectURL.appendingPathComponent("Package.swift")

        if name == nil, FileManager.default.fileExists(atPath: packageSwiftPath.path) {
            if let content = try? String(contentsOf: packageSwiftPath, encoding: .utf8),
                let match = content.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression)
            {
                let fullMatch = content[match]
                if let nameMatch = fullMatch.range(of: #""([^"]+)""#, options: .regularExpression) {
                    projectName = String(fullMatch[nameMatch].dropFirst().dropLast())
                }
            }
        }

        // Determine platforms
        let platforms: PlatformConfiguration = macosOnly ? .macOSOnly : .applePlatforms

        // Create workflows directory
        try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)

        // Generate unified CI/CD workflow
        try generateCI(
            at: workflowsDir,
            name: projectName,
            platforms: platforms,
            includeRelease: !noRelease,
        )

        print("\nWorkflow generation complete!")
    }

    // MARK: Private

    private func generateCI(
        at dir: URL,
        name: String,
        platforms: PlatformConfiguration,
        includeRelease: Bool,
    ) throws {
        let path = dir.appendingPathComponent("ci.yml")

        if FileManager.default.fileExists(atPath: path.path), !force {
            print("  ci.yml already exists (use --force to overwrite)")
            return
        }

        let workflow = DefaultConfigs.ciWorkflow(
            name: name,
            platforms: platforms,
            includeRelease: includeRelease,
        )
        try workflow.write(to: path, atomically: true, encoding: .utf8)

        if includeRelease {
            print("  Created ci.yml (unified CI/CD with release support)")
        } else {
            print("  Created ci.yml (CI only, no release jobs)")
        }
    }
}
