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
        let fileManager = FileManager.default

        print("🔄 Syncing project at \(projectURL.path)\(dryRun ? " (dry run)" : "")...\n")

        var changes: [String] = []
        var fixes: [String] = []

        // MARK: - Detect project type

        let packageSwiftPath = projectURL.appendingPathComponent("Package.swift")
        let isSwiftPackage = fileManager.fileExists(atPath: packageSwiftPath.path)

        var projectName = projectURL.lastPathComponent
        if isSwiftPackage {
            projectName = try detectPackageName(from: packageSwiftPath) ?? projectName
        }

        print("📦 Project: \(projectName)")
        print("   Type: \(isSwiftPackage ? "Swift Package" : "Xcode Project")\n")

        // MARK: - Check and create missing config files

        print("📋 Checking configuration files...")

        // .gitignore
        let gitignorePath = projectURL.appendingPathComponent(".gitignore")
        if !fileManager.fileExists(atPath: gitignorePath.path) {
            if dryRun {
                changes.append("Would create .gitignore")
            } else {
                try DefaultConfigs.gitignore.write(to: gitignorePath, atomically: true, encoding: .utf8)
                changes.append("Created .gitignore")
            }
        } else if verbose {
            print("   ✓ .gitignore exists")
        }

        // .swiftlint.yml
        let swiftlintPath = projectURL.appendingPathComponent(".swiftlint.yml")
        if !fileManager.fileExists(atPath: swiftlintPath.path) {
            if dryRun {
                changes.append("Would create .swiftlint.yml")
            } else {
                try DefaultConfigs.swiftlint.write(to: swiftlintPath, atomically: true, encoding: .utf8)
                changes.append("Created .swiftlint.yml")
            }
        } else if verbose {
            print("   ✓ .swiftlint.yml exists")
        }

        // .swiftformat
        let swiftformatPath = projectURL.appendingPathComponent(".swiftformat")
        if !fileManager.fileExists(atPath: swiftformatPath.path) {
            if dryRun {
                changes.append("Would create .swiftformat")
            } else {
                try DefaultConfigs.swiftformat.write(to: swiftformatPath, atomically: true, encoding: .utf8)
                changes.append("Created .swiftformat")
            }
        } else if verbose {
            print("   ✓ .swiftformat exists")
        }

        // CLAUDE.md
        let claudePath = projectURL.appendingPathComponent("CLAUDE.md")
        if !fileManager.fileExists(atPath: claudePath.path) {
            if dryRun {
                changes.append("Would create CLAUDE.md")
            } else {
                try DefaultConfigs.claudeMd.write(to: claudePath, atomically: true, encoding: .utf8)
                changes.append("Created CLAUDE.md")
            }
        } else if verbose {
            print("   ✓ CLAUDE.md exists")
        }

        // .github/workflows/ci.yml
        let ciWorkflowPath = projectURL.appendingPathComponent(".github/workflows/ci.yml")
        if !fileManager.fileExists(atPath: ciWorkflowPath.path) {
            if dryRun {
                changes.append("Would create .github/workflows/ci.yml")
            } else {
                let workflowsDir = ciWorkflowPath.deletingLastPathComponent()
                try fileManager.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
                let workflow = DefaultConfigs.ciWorkflow(name: projectName, platforms: .applePlatforms)
                try workflow.write(to: ciWorkflowPath, atomically: true, encoding: .utf8)
                changes.append("Created .github/workflows/ci.yml")
            }
        } else if verbose {
            print("   ✓ .github/workflows/ci.yml exists")
        }

        // .github/workflows/release.yml
        let releaseWorkflowPath = projectURL.appendingPathComponent(".github/workflows/release.yml")
        if !fileManager.fileExists(atPath: releaseWorkflowPath.path) {
            if dryRun {
                changes.append("Would create .github/workflows/release.yml")
            } else {
                let workflowsDir = releaseWorkflowPath.deletingLastPathComponent()
                try fileManager.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
                let workflow = DefaultConfigs.releaseWorkflow(name: projectName)
                try workflow.write(to: releaseWorkflowPath, atomically: true, encoding: .utf8)
                changes.append("Created .github/workflows/release.yml")
            }
        } else if verbose {
            print("   ✓ .github/workflows/release.yml exists")
        }

        // MARK: - Update dependencies

        if isSwiftPackage, !skipDeps, !dryRun {
            print("\n📦 Updating dependencies...")
            let updateResult = try await runCommand("swift", arguments: ["package", "update"], in: projectURL)
            if updateResult.exitCode == 0 {
                fixes.append("Updated package dependencies")
            } else if verbose {
                print("   ⚠ Dependency update had issues")
            }
        }

        // MARK: - Run SwiftFormat with fix

        if !skipFormat, !dryRun {
            print("\n🎨 Running SwiftFormat...")
            let formatResult = try await runCommand(
                "swiftformat",
                arguments: [".", "--config", swiftformatPath.path],
                in: projectURL,
            )
            if formatResult.exitCode == 0 {
                fixes.append("Applied SwiftFormat fixes")
            } else {
                // Try with homebrew path
                let brewFormatResult = try await runCommand(
                    "/opt/homebrew/bin/swiftformat",
                    arguments: [".", "--config", swiftformatPath.path],
                    in: projectURL,
                )
                if brewFormatResult.exitCode == 0 {
                    fixes.append("Applied SwiftFormat fixes")
                } else if verbose {
                    print("   ⚠ SwiftFormat not found or failed")
                }
            }
        }

        // MARK: - Run SwiftLint with fix

        if !skipLint, !dryRun {
            print("\n🔍 Running SwiftLint with auto-fix...")
            let lintResult = try await runCommand(
                "swiftlint",
                arguments: ["lint", "--fix", "--config", swiftlintPath.path],
                in: projectURL,
            )
            if lintResult.exitCode == 0 {
                fixes.append("Applied SwiftLint auto-fixes")
            } else {
                // Try with homebrew path
                let brewLintResult = try await runCommand(
                    "/opt/homebrew/bin/swiftlint",
                    arguments: ["lint", "--fix", "--config", swiftlintPath.path],
                    in: projectURL,
                )
                if brewLintResult.exitCode == 0 {
                    fixes.append("Applied SwiftLint auto-fixes")
                } else if verbose {
                    print("   ⚠ SwiftLint not found or failed")
                }
            }
        }

        // MARK: - Summary

        print("\n" + String(repeating: "─", count: 50))
        print("📊 Sync Summary")
        print(String(repeating: "─", count: 50))

        if changes.isEmpty, fixes.isEmpty {
            print("✅ Project is already in sync!")
        } else {
            if !changes.isEmpty {
                print("\n📁 Configuration changes:")
                for change in changes {
                    print("   • \(change)")
                }
            }

            if !fixes.isEmpty {
                print("\n🔧 Fixes applied:")
                for fix in fixes {
                    print("   • \(fix)")
                }
            }
        }

        if dryRun {
            print("\n💡 Run without --dry-run to apply changes")
        }

        print()
    }

    // MARK: Private

    // MARK: - Helpers

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
}
