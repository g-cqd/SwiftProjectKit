//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - GitIndex

/// Actor for interacting with the git index (staging area).
///
/// This actor provides thread-safe access to git operations,
/// particularly reading staged file content which differs from
/// the working directory.
///
/// ## Important
///
/// When checking files in `scope: staged`, you must read content
/// from the git index using `stagedContent(of:)`, not from disk.
/// The working directory may have unstaged changes.
public actor GitIndex {
    private let projectRoot: URL

    public init(projectRoot: URL) {
        self.projectRoot = projectRoot
    }

    // MARK: - Staged Files

    /// Get list of files in the staging area
    public func stagedFiles() async throws -> [StagedFile] {
        let output = try await runGit("diff", "--cached", "--name-status")

        return output.split(separator: "\n").compactMap { line -> StagedFile? in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count >= 2 else { return nil }

            let statusChar = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let path = String(parts[1])

            let status: StagedFile.FileStatus
            switch statusChar.first {
            case "A": status = .added
            case "M": status = .modified
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            default: status = .modified
            }

            return StagedFile(path: path, status: status, gitIndex: self)
        }
    }

    /// Get content of a file as it exists in the staging area
    ///
    /// This reads from `git show :path`, which returns the indexed
    /// (staged) version of the file, not the working directory version.
    public func stagedContent(of path: String) async throws -> String {
        try await runGit("show", ":\(path)")
    }

    // MARK: - Changed Files

    /// Get files changed compared to a base branch
    public func changedFiles(since baseBranch: String) async throws -> [String] {
        let output = try await runGit("diff", "--name-only", "\(baseBranch)...HEAD")
        return output.split(separator: "\n").map(String.init)
    }

    /// Get files changed in the current branch vs origin
    public func changedFilesVsOrigin() async throws -> [String] {
        // Get the default branch
        let defaultBranch = try await getDefaultBranch()
        return try await changedFiles(since: "origin/\(defaultBranch)")
    }

    // MARK: - Restaging

    /// Stage modified files after fixes are applied
    public func restage(files: [String]) async throws {
        guard !files.isEmpty else { return }
        try await runGit("add", arguments: files)
    }

    // MARK: - Branch Info

    /// Get the current branch name
    public func currentBranch() async throws -> String {
        try await runGit("rev-parse", "--abbrev-ref", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get the default branch (main or master)
    public func getDefaultBranch() async throws -> String {
        // Try to get from remote
        let remoteInfo = try? await runGit("remote", "show", "origin")
        if let info = remoteInfo,
            let match = info.firstMatch(of: /HEAD branch: (\w+)/)
        {
            return String(match.1)
        }

        // Fallback: check if main or master exists
        let branches = try await runGit("branch", "-l", "main", "master")
        if branches.contains("main") {
            return "main"
        }
        return "master"
    }

    // MARK: - Repository Info

    /// Check if we're in a git repository
    public func isGitRepository() async -> Bool {
        do {
            _ = try await runGit("rev-parse", "--git-dir")
            return true
        } catch {
            return false
        }
    }

    /// Get the git directory path
    public func gitDirectory() async throws -> URL {
        let path = try await runGit("rev-parse", "--git-dir")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return projectRoot.appendingPathComponent(path)
    }

    // MARK: - Hooks Directory

    /// Get or create the hooks directory
    public func hooksDirectory() async throws -> URL {
        // Check for custom hooks path first
        let customPath = try? await runGit("config", "--get", "core.hooksPath")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let customPath, !customPath.isEmpty {
            let url =
                customPath.hasPrefix("/")
                ? URL(fileURLWithPath: customPath)
                : projectRoot.appendingPathComponent(customPath)
            return url
        }

        // Default to .git/hooks
        let gitDir = try await gitDirectory()
        return gitDir.appendingPathComponent("hooks")
    }

    /// Set the hooks path to use .githooks directory
    public func setHooksPath(to path: String) async throws {
        _ = try await runGit("config", "core.hooksPath", path)
    }

    // MARK: - Private Helpers

    @discardableResult
    private func runGit(_ args: String..., arguments: [String] = []) async throws -> String {
        let allArgs = args + arguments
        return try await Shell.run("git", arguments: allArgs, in: projectRoot)
    }
}

// MARK: - OutputType

/// Type of output from a shell command
public enum OutputType: Sendable {
    case stdout
    case stderr

    public var prefix: String {
        switch self {
        case .stdout: "[stdout]"
        case .stderr: "[stderr]"
        }
    }
}

// MARK: - Shell

/// Simple shell command executor
public enum Shell {
    public static func run(
        _ command: String,
        arguments: [String] = [],
        in directory: URL? = nil
    ) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        if let directory {
            process.currentDirectoryURL = directory
        }

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ShellError.commandFailed(
                command: command,
                arguments: arguments,
                output: output,
                exitCode: process.terminationStatus
            )
        }

        return output
    }

    /// Run a command and return exit code (don't throw on non-zero)
    public static func runWithExitCode(
        _ command: String,
        arguments: [String] = [],
        in directory: URL? = nil
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        if let directory {
            process.currentDirectoryURL = directory
        }

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (output, process.terminationStatus)
    }

    /// Run a command with streaming output (for verbose mode)
    ///
    /// Streams stdout and stderr line-by-line via callback, allowing real-time output display.
    /// Returns exit code without throwing on non-zero.
    public static func runStreaming(
        _ command: String,
        arguments: [String] = [],
        in directory: URL? = nil,
        onOutput: @escaping @Sendable (String, OutputType) -> Void
    ) async throws -> Int32 {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let directory {
            process.currentDirectoryURL = directory
        }

        try process.run()

        // Stream output using async bytes
        async let stdoutTask: () = streamPipe(stdoutPipe, type: .stdout, onOutput: onOutput)
        async let stderrTask: () = streamPipe(stderrPipe, type: .stderr, onOutput: onOutput)

        // Wait for both streams to complete
        _ = await (stdoutTask, stderrTask)

        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Run a command with streaming output and also collect it
    ///
    /// Streams stdout and stderr line-by-line via callback while also collecting the full output.
    /// Returns both collected output and exit code.
    public static func runStreamingWithOutput(
        _ command: String,
        arguments: [String] = [],
        in directory: URL? = nil,
        onOutput: @escaping @Sendable (String, OutputType) -> Void
    ) async throws -> (output: String, exitCode: Int32) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let directory {
            process.currentDirectoryURL = directory
        }

        try process.run()

        // Stream and collect output using async bytes
        async let stdoutLines: [String] = streamAndCollectPipe(
            stdoutPipe,
            type: .stdout,
            onOutput: onOutput
        )
        async let stderrLines: [String] = streamAndCollectPipe(
            stderrPipe,
            type: .stderr,
            onOutput: onOutput
        )

        // Wait for both streams to complete
        let (stdout, stderr) = await (stdoutLines, stderrLines)

        process.waitUntilExit()

        let output = (stdout + stderr).joined(separator: "\n")
        return (output, process.terminationStatus)
    }

    // MARK: - Private Helpers

    private static func streamPipe(
        _ pipe: Pipe,
        type: OutputType,
        onOutput: @escaping @Sendable (String, OutputType) -> Void
    ) async {
        let handle = pipe.fileHandleForReading
        do {
            for try await line in handle.bytes.lines {
                onOutput(line, type)
            }
        } catch {
            // Ignore errors when reading from pipe (process may have terminated)
        }
    }

    private static func streamAndCollectPipe(
        _ pipe: Pipe,
        type: OutputType,
        onOutput: @escaping @Sendable (String, OutputType) -> Void
    ) async -> [String] {
        var lines: [String] = []
        let handle = pipe.fileHandleForReading
        do {
            for try await line in handle.bytes.lines {
                onOutput(line, type)
                lines.append(line)
            }
        } catch {
            // Ignore errors when reading from pipe (process may have terminated)
        }
        return lines
    }
}

// MARK: - ShellError

public enum ShellError: Error, CustomStringConvertible {
    case commandFailed(command: String, arguments: [String], output: String, exitCode: Int32)

    public var description: String {
        switch self {
        case .commandFailed(let command, let arguments, let output, let exitCode):
            let cmd = ([command] + arguments).joined(separator: " ")
            return "Command '\(cmd)' failed with exit code \(exitCode): \(output)"
        }
    }
}
