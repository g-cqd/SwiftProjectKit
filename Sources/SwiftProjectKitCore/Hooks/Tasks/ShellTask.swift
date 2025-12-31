//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation
import RegexBuilder

// MARK: - ShellTask

/// A task that runs an arbitrary shell command.
///
/// This allows projects to integrate custom tools like `swa`
/// without requiring native Swift implementations.
public struct ShellTask: HookTask {
    public let id: String
    public let name: String
    public let hooks: Set<HookType>
    public let supportsFix: Bool
    public let fixSafety: FixSafety
    public let isBlocking: Bool
    public let filePatterns: [String]

    private let command: String
    private let fixCommand: String?
    private let parseOutput: Bool
    private let successExitCodes: Set<Int32>

    public init(
        id: String,
        name: String,
        command: String,
        fixCommand: String? = nil,
        hooks: Set<HookType> = [.preCommit],
        isBlocking: Bool = true,
        fixSafety: FixSafety = .safe,
        filePatterns: [String] = ["**/*.swift"],
        parseOutput: Bool = true,
        successExitCodes: Set<Int32> = [0]
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.fixCommand = fixCommand
        self.hooks = hooks
        self.isBlocking = isBlocking
        supportsFix = fixCommand != nil
        self.fixSafety = fixSafety
        self.filePatterns = filePatterns
        self.parseOutput = parseOutput
        self.successExitCodes = successExitCodes
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        let expandedCommand = expandVariables(command, context: context)
        let parts = expandedCommand.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard let executable = parts.first else {
            return .failed(diagnostics: [
                HookDiagnostic(message: "Empty command", severity: .error)
            ])
        }

        let args = Array(parts.dropFirst())

        let (output, exitCode) = try await Shell.runWithExitCode(
            executable,
            arguments: args,
            in: context.projectRoot
        )

        let duration = ContinuousClock.now - startTime

        if successExitCodes.contains(exitCode) {
            return .passed(duration: duration)
        }

        let diagnostics: [HookDiagnostic]
        if parseOutput {
            diagnostics = parseXcodeOutput(output)
        } else {
            diagnostics = [
                HookDiagnostic(
                    message: output.isEmpty ? "Command failed with exit code \(exitCode)" : output,
                    severity: .error
                )
            ]
        }

        return .failed(
            diagnostics: diagnostics,
            duration: duration,
            fixesAvailable: fixCommand != nil
        )
    }

    public func fix(context: HookContext) async throws -> FixResult {
        guard let fixCommand else {
            return FixResult()
        }

        let expandedCommand = expandVariables(fixCommand, context: context)
        let parts = expandedCommand.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        guard let executable = parts.first else {
            return FixResult(errors: ["Empty fix command"])
        }

        let args = Array(parts.dropFirst())

        do {
            _ = try await Shell.run(executable, arguments: args, in: context.projectRoot)
            return FixResult(fixesApplied: 1)
        } catch {
            return FixResult(errors: [error.localizedDescription])
        }
    }

    // MARK: - Private

    private func expandVariables(_ command: String, context: HookContext) -> String {
        var result = command

        // ${bin:name} -> path to built binary
        // Using RegexBuilder for type-safe pattern matching
        let binPattern = Regex {
            "${"
            "bin:"
            Capture { OneOrMore(.word) }
            "}"
        }
        for match in command.matches(of: binPattern) {
            let binaryName = String(match.1)
            let binaryPath = context.projectRoot
                .appendingPathComponent(".build/debug/\(binaryName)")
                .path
            result = result.replacingOccurrences(of: String(match.0), with: binaryPath)
        }

        // ${root} -> project root
        result = result.replacingOccurrences(of: "${root}", with: context.projectRoot.path)

        // ${scope} -> staged, changed, all
        result = result.replacingOccurrences(of: "${scope}", with: context.scope.rawValue)

        return result
    }

    private func parseXcodeOutput(_ output: String) -> [HookDiagnostic] {
        // Parse Xcode-style output: file:line:col: severity: message
        // Using RegexBuilder for type-safe pattern matching
        let severityChoice = ChoiceOf {
            "error"
            "warning"
        }
        let xcodePattern = Regex {
            Anchor.startOfLine
            Capture { OneOrMore(.any, .reluctant) }  // file path
            ":"
            Capture { OneOrMore(.digit) }  // line number
            ":"
            Capture { OneOrMore(.digit) }  // column number
            ": "
            Capture { severityChoice }  // severity
            ": "
            Capture { OneOrMore(.any) }  // message
            Anchor.endOfLine
        }

        return output.split(separator: "\n").compactMap { line -> HookDiagnostic? in
            let str = String(line)
            guard let match = str.firstMatch(of: xcodePattern) else {
                // If not Xcode format, treat as plain message
                if !str.trimmingCharacters(in: .whitespaces).isEmpty {
                    return HookDiagnostic(message: str, severity: .error)
                }
                return nil
            }

            return HookDiagnostic(
                file: String(match.1),
                line: Int(match.2) ?? 0,
                column: Int(match.3) ?? 0,
                message: String(match.5),
                severity: match.4 == "error" ? .error : .warning
            )
        }
    }
}

// MARK: - BuiltInTasks

/// Factory for creating built-in hook tasks.
public enum BuiltInTasks {
    /// Format task using swift-format
    public static func format(
        paths: [String] = ["Sources/", "Tests/"],
        excludePaths: [String] = ["**/Fixtures/**"]
    ) -> FormatTask {
        FormatTask(paths: paths, excludePaths: excludePaths)
    }

    /// Build task
    public static func build(configuration: String = "debug") -> BuildTask {
        BuildTask(configuration: configuration)
    }

    /// Test task
    public static func test(parallel: Bool = true, filter: String? = nil) -> TestTask {
        TestTask(parallel: parallel, filter: filter)
    }

    /// Version sync task
    public static func versionSync(
        source: VersionSource = .default,
        syncTargets: [VersionSyncTask.SyncTarget] = []
    ) -> VersionSyncTask {
        VersionSyncTask(source: source, syncTargets: syncTargets)
    }

    /// Shell task for custom commands
    public static func shell(
        id: String,
        name: String,
        command: String,
        fixCommand: String? = nil,
        hooks: Set<HookType> = [.preCommit],
        isBlocking: Bool = true
    ) -> ShellTask {
        ShellTask(
            id: id,
            name: name,
            command: command,
            fixCommand: fixCommand,
            hooks: hooks,
            isBlocking: isBlocking
        )
    }

    /// Unused code detection task
    public static func unused(
        paths: [String] = ["Sources/"],
        isBlocking: Bool = false
    ) -> UnusedTask {
        UnusedTask(paths: paths, isBlocking: isBlocking)
    }

    /// Code duplication detection task
    public static func duplicates(
        paths: [String] = ["Sources/"],
        minTokens: Int = 100,
        isBlocking: Bool = false
    ) -> DuplicatesTask {
        DuplicatesTask(paths: paths, minTokens: minTokens, isBlocking: isBlocking)
    }

    /// All default tasks
    public static var defaults: [any HookTask] {
        [
            format(),
            build(),
            test(),
            versionSync(),
            unused(),
            duplicates(),
        ]
    }
}
