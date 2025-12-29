// swiftlint:disable no_print_statements type_body_length
import ArgumentParser
import Foundation
import SwiftProjectKitCore

struct SyncCommand: AsyncParsableCommand {
    // MARK: Internal

    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync project to standards - fill gaps, update, and fix everything",
    )

    @Option(name: .shortAndLong, help: "Path to the project")
    var path: String = "."

    @Flag(name: .long, help: "Preview changes without applying")
    var dryRun = false

    @Flag(name: .long, help: "Skip dependency updates")
    var skipDeps = false

    @Flag(name: .long, help: "Skip code formatting fixes")
    var skipFormat = false

    @Flag(name: .long, help: "Skip linting fixes")
    var skipLint = false

    @Flag(name: .long, help: "Verbose output")
    var verbose = false

    func run() async throws {
        let projectURL = URL(fileURLWithPath: path).standardizedFileURL

        print("🔄 Syncing project at \(projectURL.path)\(dryRun ? " (dry run)" : "")...\n")

        var changes: [String] = []
        var fixes: [String] = []

        // Detect project type and name
        let projectInfo = detectProjectInfo(at: projectURL)

        print("📦 Project: \(projectInfo.name)")
        print("   Type: \(projectInfo.isSwiftPackage ? "Swift Package" : "Xcode Project")\n")

        // Check and create missing config files
        print("📋 Checking configuration files...")
        try checkAndCreateConfigFiles(at: projectURL, projectName: projectInfo.name, changes: &changes)

        // Update dependencies
        if projectInfo.isSwiftPackage, !skipDeps, !dryRun {
            try await updateDependencies(at: projectURL, fixes: &fixes)
        }

        // Run SwiftFormat
        let swiftformatPath = projectURL.appendingPathComponent(".swiftformat")
        if !skipFormat, !dryRun {
            try await runSwiftFormat(at: projectURL, configPath: swiftformatPath, fixes: &fixes)
        }

        // Run SwiftLint
        let swiftlintPath = projectURL.appendingPathComponent(".swiftlint.yml")
        if !skipLint, !dryRun {
            try await runSwiftLint(at: projectURL, configPath: swiftlintPath, fixes: &fixes)
        }

        // Print summary
        printSummary(changes: changes, fixes: fixes)
    }

    // MARK: Private

    // MARK: - Project Detection

    private struct ProjectInfo {
        let name: String
        let isSwiftPackage: Bool
    }

    private func detectProjectInfo(at projectURL: URL) -> ProjectInfo {
        let fileManager = FileManager.default
        let packageSwiftPath = projectURL.appendingPathComponent("Package.swift")
        let isSwiftPackage = fileManager.fileExists(atPath: packageSwiftPath.path)

        var projectName = projectURL.lastPathComponent
        if isSwiftPackage {
            projectName = (try? detectPackageName(from: packageSwiftPath)) ?? projectName
        }

        return ProjectInfo(name: projectName, isSwiftPackage: isSwiftPackage)
    }

    private func detectPackageName(from packageSwiftPath: URL) throws -> String? {
        let content = try String(contentsOf: packageSwiftPath, encoding: .utf8)
        let pattern = #"name:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content)
        else {
            return nil
        }
        return String(content[range])
    }

    // MARK: - Config File Management

    private func checkAndCreateConfigFiles(
        at projectURL: URL,
        projectName: String,
        changes: inout [String],
    ) throws {
        try checkOrCreateGitignore(at: projectURL, changes: &changes)
        try checkOrCreateSwiftLintConfig(at: projectURL, changes: &changes)
        try checkOrCreateSwiftFormatConfig(at: projectURL, changes: &changes)
        try checkOrCreateClaudeMd(at: projectURL, changes: &changes)
        // CI workflow includes release support (unified CI/CD)
        try checkOrCreateCIWorkflow(at: projectURL, projectName: projectName, changes: &changes)
    }

    private func checkOrCreateGitignore(at projectURL: URL, changes: inout [String]) throws {
        let filePath = projectURL.appendingPathComponent(".gitignore")
        try checkOrCreateConfigFile(
            at: filePath,
            content: DefaultConfigs.gitignore,
            fileName: ".gitignore",
            changes: &changes,
        )
    }

    private func checkOrCreateSwiftLintConfig(at projectURL: URL, changes: inout [String]) throws {
        let filePath = projectURL.appendingPathComponent(".swiftlint.yml")
        try checkOrCreateConfigFile(
            at: filePath,
            content: DefaultConfigs.swiftlint,
            fileName: ".swiftlint.yml",
            changes: &changes,
        )
    }

    private func checkOrCreateSwiftFormatConfig(at projectURL: URL, changes: inout [String]) throws {
        let filePath = projectURL.appendingPathComponent(".swiftformat")
        try checkOrCreateConfigFile(
            at: filePath,
            content: DefaultConfigs.swiftformat,
            fileName: ".swiftformat",
            changes: &changes,
        )
    }

    private func checkOrCreateClaudeMd(at projectURL: URL, changes: inout [String]) throws {
        let filePath = projectURL.appendingPathComponent("CLAUDE.md")
        try checkOrCreateConfigFile(
            at: filePath,
            content: DefaultConfigs.claudeMd,
            fileName: "CLAUDE.md",
            changes: &changes,
        )
    }

    private func checkOrCreateCIWorkflow(
        at projectURL: URL,
        projectName: String,
        changes: inout [String],
    ) throws {
        let filePath = projectURL.appendingPathComponent(".github/workflows/ci.yml")
        // Unified CI/CD workflow includes release support
        let content = DefaultConfigs.ciWorkflow(name: projectName, platforms: .applePlatforms)
        try checkOrCreateConfigFile(
            at: filePath,
            content: content,
            fileName: ".github/workflows/ci.yml",
            changes: &changes,
            createIntermediateDirectories: true,
        )
    }

    private func checkOrCreateConfigFile(
        at filePath: URL,
        content: String,
        fileName: String,
        changes: inout [String],
        createIntermediateDirectories: Bool = false,
    ) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: filePath.path) {
            if verbose {
                print("   ✓ \(fileName) exists")
            }
            return
        }

        if dryRun {
            changes.append("Would create \(fileName)")
            return
        }

        if createIntermediateDirectories {
            let parentDirectory = filePath.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        try content.write(to: filePath, atomically: true, encoding: .utf8)
        changes.append("Created \(fileName)")
    }

    // MARK: - Dependency Updates

    private func updateDependencies(at projectURL: URL, fixes: inout [String]) async throws {
        print("\n📦 Updating dependencies...")
        let updateResult = try await runCommand("swift", arguments: ["package", "update"], in: projectURL)
        if updateResult.exitCode == 0 {
            fixes.append("Updated package dependencies")
        } else if verbose {
            print("   ⚠ Dependency update had issues")
        }
    }

    // MARK: - Tool Execution

    private func runSwiftFormat(at projectURL: URL, configPath: URL, fixes: inout [String]) async throws {
        print("\n🎨 Running SwiftFormat...")
        let success = try await runToolWithFallback(
            primaryPath: "swiftformat",
            fallbackPath: "/opt/homebrew/bin/swiftformat",
            arguments: [".", "--config", configPath.path],
            in: projectURL,
        )
        if success {
            fixes.append("Applied SwiftFormat fixes")
        } else if verbose {
            print("   ⚠ SwiftFormat not found or failed")
        }
    }

    private func runSwiftLint(at projectURL: URL, configPath: URL, fixes: inout [String]) async throws {
        print("\n🔍 Running SwiftLint with auto-fix...")
        let success = try await runToolWithFallback(
            primaryPath: "swiftlint",
            fallbackPath: "/opt/homebrew/bin/swiftlint",
            arguments: ["lint", "--fix", "--config", configPath.path],
            in: projectURL,
        )
        if success {
            fixes.append("Applied SwiftLint auto-fixes")
        } else if verbose {
            print("   ⚠ SwiftLint not found or failed")
        }
    }

    private func runToolWithFallback(
        primaryPath: String,
        fallbackPath: String,
        arguments: [String],
        in directory: URL,
    ) async throws -> Bool {
        let primaryResult = try await runCommand(primaryPath, arguments: arguments, in: directory)
        if primaryResult.exitCode == 0 {
            return true
        }

        let fallbackResult = try await runCommand(fallbackPath, arguments: arguments, in: directory)
        return fallbackResult.exitCode == 0
    }

    private func runCommand(
        _ executable: String,
        arguments: [String],
        in directory: URL,
    ) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    // MARK: - Summary

    private func printSummary(changes: [String], fixes: [String]) {
        print("\n" + String(repeating: "─", count: 50))
        print("📊 Sync Summary")
        print(String(repeating: "─", count: 50))

        if changes.isEmpty, fixes.isEmpty {
            print("✅ Project is already in sync!")
        } else {
            printChangesSection(changes)
            printFixesSection(fixes)
        }

        if dryRun {
            print("\n💡 Run without --dry-run to apply changes")
        }

        print()
    }

    private func printChangesSection(_ changes: [String]) {
        guard !changes.isEmpty else { return }

        print("\n📁 Configuration changes:")
        for change in changes {
            print("   • \(change)")
        }
    }

    private func printFixesSection(_ fixes: [String]) {
        guard !fixes.isEmpty else { return }

        print("\n🔧 Fixes applied:")
        for fix in fixes {
            print("   • \(fix)")
        }
    }
}
