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

    @Flag(name: .long, help: "Include static analysis (unused code, duplicates)")
    var staticAnalysis = false

    @Flag(name: .long, help: "Include documentation generation and deployment")
    var docs = false

    @Option(name: .long, help: "Target for documentation generation (required with --docs)")
    var docsTarget: String?

    @Option(name: .long, help: "Hosting base path for docs (defaults to project name)")
    var hostingBasePath: String?

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

        // Validate docs options
        if docs, docsTarget == nil {
            print("Error: --docs-target is required when using --docs")
            return
        }

        // Generate unified CI/CD workflow
        try generateCI(
            at: workflowsDir,
            name: projectName,
            platforms: platforms,
            includeRelease: !noRelease,
            includeStaticAnalysis: staticAnalysis,
            includeDocs: docs,
            docsTarget: docsTarget,
            hostingBasePath: hostingBasePath,
        )

        print("\nWorkflow generation complete!")
    }

    // MARK: Private

    private func generateCI(
        at dir: URL,
        name: String,
        platforms: PlatformConfiguration,
        includeRelease: Bool,
        includeStaticAnalysis: Bool,
        includeDocs: Bool,
        docsTarget: String?,
        hostingBasePath: String?,
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
            includeStaticAnalysis: includeStaticAnalysis,
            includeDocs: includeDocs,
            docsTarget: docsTarget,
            hostingBasePath: hostingBasePath,
        )
        try workflow.write(to: path, atomically: true, encoding: .utf8)

        var features: [String] = []
        if includeRelease { features.append("release") }
        if includeStaticAnalysis { features.append("static analysis") }
        if includeDocs { features.append("docs") }

        if features.isEmpty {
            print("  Created ci.yml (CI only)")
        } else {
            print("  Created ci.yml (CI with \(features.joined(separator: ", ")))")
        }
    }
}
