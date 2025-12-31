//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import SwiftProjectKitCore

// MARK: - AnalyzeCommand

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Run static analysis on your Swift code",
        discussion: """
            Runs SwiftStaticAnalysis tools to detect code quality issues.

            Available analyses:
              • unused     - Detect unused code (variables, functions, types)
              • duplicates - Detect code duplication (clones)

            Without a subcommand, runs all analyses.
            """,
        subcommands: [Unused.self, Duplicates.self],
        defaultSubcommand: nil
    )

    // MARK: - Options

    @Flag(name: .long, help: "Use stricter thresholds for detection")
    var strict = false

    @Option(name: .long, help: "Paths to analyze (default: Sources/)")
    var paths: [String] = []

    @Option(name: .long, help: "Paths to exclude from analysis")
    var excludePaths: [String] = []

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose = false

    // MARK: - Run (all analyses)

    func run() async throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let swaPath = try await ensureSWA()

        print("🔍 Running static analysis...\n")

        // Run unused code detection
        print("▸ Detecting unused code...")
        try await runUnusedAnalysis(swaPath: swaPath, projectRoot: projectRoot)

        print()

        // Run duplication detection
        print("▸ Detecting code duplicates...")
        try await runDuplicatesAnalysis(swaPath: swaPath, projectRoot: projectRoot)

        print("\n✅ Static analysis completed!")
    }

    // MARK: - Analysis Methods

    func runUnusedAnalysis(swaPath: URL, projectRoot: URL) async throws {
        var args = ["unused"]

        // Determine paths to analyze
        let analyzePaths = paths.isEmpty ? [projectRoot.path] : paths
        args.append(contentsOf: analyzePaths)

        // Add config file if exists
        if let configPath = findConfigFile(in: projectRoot) {
            args += ["--config", configPath.path]
        }

        // Default exclusions
        args += ["--exclude-paths", ".build"]
        args += ["--exclude-paths", "DerivedData"]

        // User exclusions
        for path in excludePaths {
            args += ["--exclude-paths", path]
        }

        args += ["--mode", "reachability"]
        args += ["--sensible-defaults"]
        args += ["--format", "text"]

        if strict {
            args += ["--min-confidence", "low"]
        }

        try runProcess(executableURL: swaPath, arguments: args, currentDirectory: projectRoot)
    }

    func runDuplicatesAnalysis(swaPath: URL, projectRoot: URL) async throws {
        var args = ["duplicates"]

        // Determine paths to analyze
        let analyzePaths = paths.isEmpty ? [projectRoot.path] : paths
        args.append(contentsOf: analyzePaths)

        // Add config file if exists
        if let configPath = findConfigFile(in: projectRoot) {
            args += ["--config", configPath.path]
        }

        // Default exclusions
        args += ["--exclude-paths", ".build"]
        args += ["--exclude-paths", "DerivedData"]

        // User exclusions
        for path in excludePaths {
            args += ["--exclude-paths", path]
        }

        args += ["--format", "text"]

        // Token threshold
        if strict {
            args += ["--min-tokens", "30"]
        } else {
            args += ["--min-tokens", "100"]
        }

        try runProcess(executableURL: swaPath, arguments: args, currentDirectory: projectRoot)
    }

    // MARK: - Helpers

    func ensureSWA() async throws -> URL {
        // Check system PATH first
        if let systemPath = findInPath("swa") {
            if verbose {
                print("Using system-installed swa at \(systemPath.path)")
            }
            return systemPath
        }

        // Use BinaryManager to fetch SWA
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spk")
            .appendingPathComponent("bin")
        let manager = BinaryManager(cacheDirectory: cacheDir)
        return try await manager.ensureBinary(for: ManagedTool.swa)
    }

    func findConfigFile(in directory: URL) -> URL? {
        let configNames = [".swa.json", "swa.json"]
        for name in configNames {
            let path = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    func runProcess(executableURL: URL, arguments: [String], currentDirectory: URL) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        if verbose {
            print("  Running: \(executableURL.lastPathComponent) \(arguments.joined(separator: " "))")
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Read pipes concurrently to avoid deadlock
        let group = DispatchGroup()
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()

        group.enter()
        DispatchQueue.global().async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.wait()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errors = String(data: errorData, encoding: .utf8) ?? ""

        if !output.isEmpty {
            print(output)
        }
        if !errors.isEmpty, process.terminationStatus != 0 {
            print(errors)
        }

        if process.terminationStatus != 0 {
            throw AnalyzeError.analysisFailed(exitCode: process.terminationStatus)
        }
    }
}

// MARK: - Unused Subcommand

extension AnalyzeCommand {
    struct Unused: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "unused",
            abstract: "Detect unused code in your project"
        )

        @OptionGroup var options: AnalyzeCommand

        @Option(name: .long, help: "Detection mode (simple, reachability)")
        var mode: String = "reachability"

        @Option(name: .long, help: "Minimum confidence level (low, medium, high)")
        var minConfidence: String?

        @Flag(name: .long, help: "Ignore public declarations")
        var ignorePublic = false

        func run() async throws {
            let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let swaPath = try await options.ensureSWA()

            print("🔍 Detecting unused code...\n")

            var args = ["unused"]

            // Determine paths to analyze
            let analyzePaths = options.paths.isEmpty ? [projectRoot.path] : options.paths
            args.append(contentsOf: analyzePaths)

            // Add config file if exists
            if let configPath = options.findConfigFile(in: projectRoot) {
                args += ["--config", configPath.path]
            }

            // Default exclusions
            args += ["--exclude-paths", ".build"]
            args += ["--exclude-paths", "DerivedData"]

            // User exclusions
            for path in options.excludePaths {
                args += ["--exclude-paths", path]
            }

            args += ["--mode", mode]
            args += ["--sensible-defaults"]
            args += ["--format", "text"]

            if let confidence = minConfidence {
                args += ["--min-confidence", confidence]
            } else if options.strict {
                args += ["--min-confidence", "low"]
            }

            if ignorePublic {
                args.append("--ignore-public")
            }

            try options.runProcess(executableURL: swaPath, arguments: args, currentDirectory: projectRoot)

            print("\n✅ Unused code detection completed!")
        }
    }
}

// MARK: - Duplicates Subcommand

extension AnalyzeCommand {
    struct Duplicates: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "duplicates",
            abstract: "Detect code duplication in your project"
        )

        @OptionGroup var options: AnalyzeCommand

        @Option(name: .long, help: "Minimum tokens for clone detection")
        var minTokens: Int?

        @Option(name: .long, help: "Clone types to detect (exact, near, semantic)")
        var types: [String] = []

        @Option(name: .long, help: "Detection algorithm")
        var algorithm: String?

        func run() async throws {
            let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let swaPath = try await options.ensureSWA()

            print("🔍 Detecting code duplicates...\n")

            var args = ["duplicates"]

            // Determine paths to analyze
            let analyzePaths = options.paths.isEmpty ? [projectRoot.path] : options.paths
            args.append(contentsOf: analyzePaths)

            // Add config file if exists
            if let configPath = options.findConfigFile(in: projectRoot) {
                args += ["--config", configPath.path]
            }

            // Default exclusions
            args += ["--exclude-paths", ".build"]
            args += ["--exclude-paths", "DerivedData"]

            // User exclusions
            for path in options.excludePaths {
                args += ["--exclude-paths", path]
            }

            args += ["--format", "text"]

            // Token threshold
            if let tokens = minTokens {
                args += ["--min-tokens", String(tokens)]
            } else if options.strict {
                args += ["--min-tokens", "30"]
            } else {
                args += ["--min-tokens", "100"]
            }

            for type in types {
                args += ["--types", type]
            }

            if let alg = algorithm {
                args += ["--algorithm", alg]
            }

            try options.runProcess(executableURL: swaPath, arguments: args, currentDirectory: projectRoot)

            print("\n✅ Duplication detection completed!")
        }
    }
}

// MARK: - PATH Lookup

private func findInPath(_ executable: String) -> URL? {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let searchPaths = [
        homeDir.appendingPathComponent(".local/bin").path,
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let allPaths = searchPaths + envPath.split(separator: ":").map(String.init)

    for dir in allPaths {
        let fullPath = URL(fileURLWithPath: dir).appendingPathComponent(executable)
        if FileManager.default.isExecutableFile(atPath: fullPath.path) {
            return fullPath
        }
    }
    return nil
}

// MARK: - AnalyzeError

enum AnalyzeError: Error, CustomStringConvertible {
    case analysisFailed(exitCode: Int32)

    var description: String {
        switch self {
        case .analysisFailed(let exitCode):
            "Analysis failed with exit code \(exitCode)"
        }
    }
}
