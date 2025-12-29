import ArgumentParser
import Foundation
import SwiftProjectKitCore

struct UpdateCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update project configuration files to latest standards",
    )

    @Option(name: .shortAndLong, help: "Path to the project")
    var path: String = "."

    @Flag(name: .long, help: "Update SwiftLint rules")
    var swiftlint = false

    @Flag(name: .long, help: "Update SwiftFormat rules")
    var swiftformat = false

    @Flag(name: .long, help: "Update GitHub workflows")
    var workflows = false

    @Flag(name: .long, help: "Update CLAUDE.md")
    var claude = false

    @Flag(name: .long, help: "Update all configurations")
    var all = false

    @Flag(name: .long, help: "Preview changes without applying")
    var dryRun = false

    func run() async throws {
        let projectURL = URL(fileURLWithPath: path)

        let updateSwiftlint = all || swiftlint
        let updateSwiftformat = all || swiftformat
        let updateWorkflows = all || workflows
        let updateClaude = all || claude

        if !updateSwiftlint, !updateSwiftformat, !updateWorkflows, !updateClaude {
            print("No update options specified. Use --all or specific flags.")
            print("Options: --swiftlint, --swiftformat, --workflows, --claude, --all")
            return
        }

        print("Updating project at \(projectURL.path)\(dryRun ? " (dry run)" : "")...")

        if updateSwiftlint {
            try updateSwiftLintConfig(at: projectURL)
        }

        if updateSwiftformat {
            try updateSwiftFormatConfig(at: projectURL)
        }

        if updateClaude {
            try updateClaudeConfig(at: projectURL)
        }

        if updateWorkflows {
            try updateWorkflowsConfig(at: projectURL)
        }

        print("\nUpdate complete\(dryRun ? " (dry run)" : "")!")
    }

    // MARK: Private

    private func updateSwiftLintConfig(at projectURL: URL) throws {
        let configPath = projectURL.appendingPathComponent(".swiftlint.yml")
        if dryRun {
            print("  Would update .swiftlint.yml")
        } else {
            try DefaultConfigs.swiftlint.write(to: configPath, atomically: true, encoding: .utf8)
            print("  Updated .swiftlint.yml")
        }
    }

    private func updateSwiftFormatConfig(at projectURL: URL) throws {
        let configPath = projectURL.appendingPathComponent(".swiftformat")
        if dryRun {
            print("  Would update .swiftformat")
        } else {
            try DefaultConfigs.swiftformat.write(to: configPath, atomically: true, encoding: .utf8)
            print("  Updated .swiftformat")
        }
    }

    private func updateClaudeConfig(at projectURL: URL) throws {
        let configPath = projectURL.appendingPathComponent("CLAUDE.md")
        if dryRun {
            print("  Would update CLAUDE.md")
        } else {
            try DefaultConfigs.claudeMd.write(to: configPath, atomically: true, encoding: .utf8)
            print("  Updated CLAUDE.md")
        }
    }

    private func updateWorkflowsConfig(at projectURL: URL) throws {
        let projectName = detectProjectName(at: projectURL)
        let workflowsDir = projectURL.appendingPathComponent(".github/workflows")
        let ciPath = workflowsDir.appendingPathComponent("ci.yml")

        if dryRun {
            print("  Would update .github/workflows/ci.yml")
        } else {
            try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
            let workflow = DefaultConfigs.ciWorkflow(name: projectName, platforms: .applePlatforms)
            try workflow.write(to: ciPath, atomically: true, encoding: .utf8)
            print("  Updated .github/workflows/ci.yml")
        }
    }

    private func detectProjectName(at projectURL: URL) -> String {
        let packageSwiftPath = projectURL.appendingPathComponent("Package.swift")
        var projectName = projectURL.lastPathComponent

        if FileManager.default.fileExists(atPath: packageSwiftPath.path),
           let content = try? String(contentsOf: packageSwiftPath, encoding: .utf8),
           let match = content.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression),
           let nameRange = content[match].range(of: #""([^"]+)""#, options: .regularExpression) {
            projectName = String(content[nameRange].dropFirst().dropLast())
        }

        return projectName
    }
}
