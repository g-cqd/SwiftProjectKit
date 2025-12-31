//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - UnusedTask

/// Task that runs unused code detection using SwiftStaticAnalysis.
public struct UnusedTask: HookTask {
    public let id = "unused"
    public let name = "Unused Code"
    public let hooks: Set<HookType> = [.prePush, .ci]
    public let isBlocking: Bool
    public let fixSafety = FixSafety.cautious
    public let supportsFix = false

    private let paths: [String]
    private let excludePaths: [String]
    private let mode: String
    private let sensibleDefaults: Bool

    public init(
        paths: [String] = ["Sources/"],
        excludePaths: [String] = [".build", "DerivedData"],
        mode: String = "reachability",
        sensibleDefaults: Bool = true,
        isBlocking: Bool = false
    ) {
        self.paths = paths
        self.excludePaths = excludePaths
        self.mode = mode
        self.sensibleDefaults = sensibleDefaults
        self.isBlocking = isBlocking
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let clock = ContinuousClock()
        let start = clock.now

        guard let swaPath = await findSWA() else {
            return .skipped(reason: "swa binary not found")
        }

        var args = ["unused"]

        // Add paths
        for path in paths {
            let fullPath = context.projectRoot.appendingPathComponent(path).path
            args.append(fullPath)
        }

        // Exclusions
        for exclude in excludePaths {
            args += ["--exclude-paths", exclude]
        }

        args += ["--mode", mode]
        args += ["--format", "text"]

        if sensibleDefaults {
            args.append("--sensible-defaults")
        }

        let result: (output: String, exitCode: Int32)

        if context.verbose {
            result = try await runProcessStreaming(
                executableURL: swaPath,
                arguments: args,
                currentDirectory: context.projectRoot
            )
        } else {
            result = try await runProcess(
                executableURL: swaPath,
                arguments: args,
                currentDirectory: context.projectRoot
            )
        }

        let duration = clock.now - start

        guard result.exitCode != 0 else {
            return .passed(duration: duration)
        }

        let diagnostics = parseOutput(result.output, projectRoot: context.projectRoot)
        return TaskResult(
            status: isBlocking ? .failed : .warning,
            diagnostics: diagnostics,
            duration: duration
        )
    }

    public func fix(context: HookContext) async throws -> FixResult {
        FixResult()
    }

    private func findSWA() async -> URL? {
        // Check common paths
        let searchPaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/swa"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".spk/bin/swa"),
            URL(fileURLWithPath: "/opt/homebrew/bin/swa"),
            URL(fileURLWithPath: "/usr/local/bin/swa"),
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }

        // Check PATH
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let path = URL(fileURLWithPath: String(dir)).appendingPathComponent("swa")
            if FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }

        // Try BinaryManager
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spk")
            .appendingPathComponent("bin")
        let manager = BinaryManager(cacheDirectory: cacheDir)
        return try? await manager.ensureBinary(for: .swa)
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errors = String(data: errorData, encoding: .utf8) ?? ""

        return (output + errors, process.terminationStatus)
    }

    private func runProcessStreaming(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Stream and collect output
        async let stdoutLines = streamAndCollect(stdoutPipe, type: .stdout)
        async let stderrLines = streamAndCollect(stderrPipe, type: .stderr)

        let (stdout, stderr) = await (stdoutLines, stderrLines)

        process.waitUntilExit()

        let output = (stdout + stderr).joined(separator: "\n")
        return (output, process.terminationStatus)
    }

    private func streamAndCollect(_ pipe: Pipe, type: OutputType) async -> [String] {
        var lines: [String] = []
        let handle = pipe.fileHandleForReading
        do {
            for try await line in handle.bytes.lines {
                print("\(type.prefix) \(line)")
                fflush(stdout)
                lines.append(line)
            }
        } catch {
            // Ignore errors when reading from pipe (process may have terminated)
        }
        return lines
    }

    private func parseOutput(_ output: String, projectRoot: URL) -> [HookDiagnostic] {
        var diagnostics: [HookDiagnostic] = []

        for line in output.split(separator: "\n") {
            let lineStr = String(line)
            // Parse lines like: [high] /path/file.swift:123:45: message
            if lineStr.hasPrefix("[") {
                if let diagnostic = parseDiagnosticLine(lineStr) {
                    diagnostics.append(diagnostic)
                }
            }
        }

        return diagnostics
    }

    private func parseDiagnosticLine(_ line: String) -> HookDiagnostic? {
        // Format: [severity] /path:line:col: message
        guard let bracketEnd = line.firstIndex(of: "]") else { return nil }

        let severityStart = line.index(after: line.startIndex)
        let severityStr = String(line[severityStart ..< bracketEnd])

        let severity: HookSeverity =
            switch severityStr {
            case "high": .error
            case "medium": .warning
            default: .info
            }

        let rest = String(line[line.index(after: bracketEnd)...]).trimmingCharacters(in: .whitespaces)

        // Find file:line:col pattern
        if let colonIndex = rest.firstIndex(of: ":") {
            let file = String(rest[..<colonIndex])
            let message = String(rest[rest.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            return HookDiagnostic(
                file: file,
                message: message,
                severity: severity,
                ruleID: "unused"
            )
        }

        return HookDiagnostic(message: rest, severity: severity, ruleID: "unused")
    }
}

// MARK: - DuplicatesTask

/// Task that runs code duplication detection using SwiftStaticAnalysis.
public struct DuplicatesTask: HookTask {
    public let id = "duplicates"
    public let name = "Duplicates"
    public let hooks: Set<HookType> = [.prePush, .ci]
    public let isBlocking: Bool
    public let fixSafety = FixSafety.cautious
    public let supportsFix = false

    private let paths: [String]
    private let excludePaths: [String]
    private let minTokens: Int

    public init(
        paths: [String] = ["Sources/"],
        excludePaths: [String] = [".build", "DerivedData"],
        minTokens: Int = 100,
        isBlocking: Bool = false
    ) {
        self.paths = paths
        self.excludePaths = excludePaths
        self.minTokens = minTokens
        self.isBlocking = isBlocking
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let clock = ContinuousClock()
        let start = clock.now

        guard let swaPath = await findSWA() else {
            return .skipped(reason: "swa binary not found")
        }

        var args = ["duplicates"]

        // Add paths
        for path in paths {
            let fullPath = context.projectRoot.appendingPathComponent(path).path
            args.append(fullPath)
        }

        // Exclusions
        for exclude in excludePaths {
            args += ["--exclude-paths", exclude]
        }

        args += ["--min-tokens", String(minTokens)]
        args += ["--format", "text"]

        let result: (output: String, exitCode: Int32)

        if context.verbose {
            result = try await runProcessStreaming(
                executableURL: swaPath,
                arguments: args,
                currentDirectory: context.projectRoot
            )
        } else {
            result = try await runProcess(
                executableURL: swaPath,
                arguments: args,
                currentDirectory: context.projectRoot
            )
        }

        let duration = clock.now - start

        // Check if no duplicates were found
        guard result.exitCode != 0 || (!result.output.contains("Found 0 clone") && !result.output.isEmpty)
        else {
            return .passed(duration: duration)
        }

        // Duplicates found or error occurred
        let diagnostics = parseOutput(result.output)
        return TaskResult(
            status: isBlocking ? .failed : .warning,
            diagnostics: diagnostics,
            duration: duration
        )
    }

    public func fix(context: HookContext) async throws -> FixResult {
        FixResult()
    }

    private func findSWA() async -> URL? {
        let searchPaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/swa"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".spk/bin/swa"),
            URL(fileURLWithPath: "/opt/homebrew/bin/swa"),
            URL(fileURLWithPath: "/usr/local/bin/swa"),
        ]

        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }

        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let path = URL(fileURLWithPath: String(dir)).appendingPathComponent("swa")
            if FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }

        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spk")
            .appendingPathComponent("bin")
        let manager = BinaryManager(cacheDirectory: cacheDir)
        return try? await manager.ensureBinary(for: .swa)
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errors = String(data: errorData, encoding: .utf8) ?? ""

        return (output + errors, process.terminationStatus)
    }

    private func runProcessStreaming(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Stream and collect output
        async let stdoutLines = streamAndCollect(stdoutPipe, type: .stdout)
        async let stderrLines = streamAndCollect(stderrPipe, type: .stderr)

        let (stdout, stderr) = await (stdoutLines, stderrLines)

        process.waitUntilExit()

        let output = (stdout + stderr).joined(separator: "\n")
        return (output, process.terminationStatus)
    }

    private func streamAndCollect(_ pipe: Pipe, type: OutputType) async -> [String] {
        var lines: [String] = []
        let handle = pipe.fileHandleForReading
        do {
            for try await line in handle.bytes.lines {
                print("\(type.prefix) \(line)")
                fflush(stdout)
                lines.append(line)
            }
        } catch {
            // Ignore errors when reading from pipe (process may have terminated)
        }
        return lines
    }

    private func parseOutput(_ output: String) -> [HookDiagnostic] {
        var diagnostics: [HookDiagnostic] = []

        // Parse clone groups
        var currentGroup: String?
        for line in output.split(separator: "\n") {
            let lineStr = String(line)

            if lineStr.starts(with: "[") && lineStr.contains("clone") {
                currentGroup = lineStr
            } else if lineStr.starts(with: "  -") {
                // File location line
                let location = lineStr.dropFirst(4)  // Remove "  - "
                if let group = currentGroup {
                    diagnostics.append(
                        HookDiagnostic(
                            file: String(location),
                            message: group,
                            severity: .warning,
                            ruleID: "duplicates"
                        )
                    )
                }
            }
        }

        return diagnostics
    }
}
