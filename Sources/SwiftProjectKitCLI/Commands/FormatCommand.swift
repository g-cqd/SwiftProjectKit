// swiftlint:disable no_print_statements
import ArgumentParser
import Foundation
import SwiftProjectKitCore

struct FormatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Run SwiftFormat on the project",
    )

    @Option(name: .shortAndLong, help: "Path to format")
    var path: String = "."

    @Flag(name: .long, help: "Check only - don't modify files")
    var lint = false

    @Flag(name: .long, help: "Verbose output")
    var verbose = false

    func run() async throws {
        let projectURL = URL(fileURLWithPath: path)

        // Download SwiftFormat if needed
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("spk-cache")
        let binaryManager = BinaryManager(cacheDirectory: cacheDir)

        print("Ensuring SwiftFormat is available...")
        let swiftformatPath = try await binaryManager.ensureBinary(for: .swiftformat)

        // Build arguments
        var args: [String] = []
        if lint {
            args.append("--lint")
        }
        if verbose {
            args.append("--verbose")
        }

        // Find config
        let configPath = projectURL.appendingPathComponent(".swiftformat")
        if FileManager.default.fileExists(atPath: configPath.path) {
            args += ["--config", configPath.path]
        }

        // Add path
        args.append(projectURL.path)

        print("Running SwiftFormat\(lint ? " (lint mode)" : "")...")

        let process = Process()
        process.executableURL = swiftformatPath
        process.arguments = args
        process.currentDirectoryURL = projectURL

        try process.run()
        process.waitUntilExit()

        let action = lint ? "checked" : "formatted"
        if process.terminationStatus == 0 {
            print("SwiftFormat \(action) successfully")
        } else {
            print("SwiftFormat found issues (exit code: \(process.terminationStatus))")
            throw ExitCode(process.terminationStatus)
        }
    }
}
