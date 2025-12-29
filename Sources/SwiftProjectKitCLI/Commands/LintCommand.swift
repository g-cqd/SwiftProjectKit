import ArgumentParser
import Foundation
import SwiftProjectKitCore

struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Run SwiftLint on the project",
    )

    @Option(name: .shortAndLong, help: "Path to lint")
    var path: String = "."

    @Flag(name: .long, help: "Automatically fix violations")
    var fix = false

    @Flag(name: .long, help: "Strict mode - fail on warnings")
    var strict = false

    func run() async throws {
        let projectURL = URL(fileURLWithPath: path)

        // Download SwiftLint if needed
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("spk-cache")
        let binaryManager = BinaryManager(cacheDirectory: cacheDir)

        print("Ensuring SwiftLint is available...")
        let swiftlintPath = try await binaryManager.ensureBinary(for: .swiftlint)

        // Build arguments
        var args = fix ? ["lint", "--fix"] : ["lint"]
        if strict {
            args.append("--strict")
        }
        args.append("--reporter")
        args.append("xcode")

        // Find config
        let configPath = projectURL.appendingPathComponent(".swiftlint.yml")
        if FileManager.default.fileExists(atPath: configPath.path) {
            args += ["--config", configPath.path]
        }

        // Add path
        args.append(projectURL.path)

        print("Running SwiftLint...")

        let process = Process()
        process.executableURL = swiftlintPath
        process.arguments = args
        process.currentDirectoryURL = projectURL

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("SwiftLint completed successfully")
        } else {
            print("SwiftLint found issues (exit code: \(process.terminationStatus))")
            throw ExitCode(process.terminationStatus)
        }
    }
}
