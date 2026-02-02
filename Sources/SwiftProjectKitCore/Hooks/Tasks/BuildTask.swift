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

// MARK: - BuildTask

/// Task that builds the Swift package.
public struct BuildTask: HookTask {
    public let id = "build"
    public let name = "Build"
    public let hooks: Set<HookType> = [.preCommit, .prePush, .ci]
    public let supportsFix = false
    public let fixSafety: FixSafety = .safe
    public let isBlocking = true
    public let filePatterns = ["**/*.swift", "Package.swift"]

    private let configuration: String
    private let scheme: String?
    private let project: String?
    private let destination: String?

    public init(
        configuration: String = "debug",
        scheme: String? = nil,
        project: String? = nil,
        destination: String? = nil
    ) {
        self.configuration = configuration
        self.scheme = scheme
        self.project = project
        self.destination = destination
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        let command: String
        let args: [String]

        if let scheme {
            command = "xcodebuild"
            var xcodebuildArgs: [String] = []
            if let project { xcodebuildArgs += ["-project", project] }
            xcodebuildArgs += ["-scheme", scheme, "build", "-configuration", configuration]
            if let destination { xcodebuildArgs += ["-destination", destination] }
            args = xcodebuildArgs
        } else {
            command = "swift"
            args = ["build", "-c", configuration]
        }

        let output: String
        let exitCode: Int32

        if context.verbose {
            (output, exitCode) = try await Shell.runStreamingWithOutput(
                command,
                arguments: args,
                in: context.projectRoot,
                onOutput: verboseOutputHandler
            )
        } else {
            (output, exitCode) = try await Shell.runWithExitCode(
                command,
                arguments: args,
                in: context.projectRoot
            )
        }

        let duration = ContinuousClock.now - startTime

        if exitCode == 0 {
            return .passed(duration: duration)
        }

        let diagnostics = parseBuildOutput(output)
        return .failed(diagnostics: diagnostics, duration: duration)
    }

    // MARK: - Verbose Output

    private func verboseOutputHandler(_ line: String, _ type: OutputType) {
        print("\(type.prefix) \(line)")
        fflush(stdout)
    }

    // MARK: - Private

    private func parseBuildOutput(_ output: String) -> [HookDiagnostic] {
        // Swift compiler outputs lines like:
        // /path/to/file.swift:10:5: error: message
        // Using RegexBuilder for type-safe pattern matching
        let severityChoice = ChoiceOf {
            "error"
            "warning"
            "note"
        }
        let buildPattern = Regex {
            Anchor.startOfLine
            Capture {
                OneOrMore(.any, .reluctant)
                ".swift"
            }  // file path ending in .swift
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
            guard let match = str.firstMatch(of: buildPattern) else {
                return nil
            }

            let file = String(match.1)
            let lineNum = Int(match.2) ?? 0
            let column = Int(match.3) ?? 0
            let severityStr = String(match.4)
            let message = String(match.5)

            let severity: HookSeverity
            switch severityStr {
            case "error": severity = .error
            case "warning": severity = .warning
            default: severity = .info
            }

            return HookDiagnostic(
                file: file,
                line: lineNum,
                column: column,
                message: message,
                severity: severity
            )
        }
    }
}

// MARK: - TestTask

/// Task that runs the Swift package tests.
public struct TestTask: HookTask {
    public let id = "test"
    public let name = "Test"
    public let hooks: Set<HookType> = [.prePush, .ci]
    public let supportsFix = false
    public let fixSafety: FixSafety = .safe
    public let isBlocking = true
    public let filePatterns = ["**/*.swift"]

    private let parallel: Bool
    private let filter: String?
    private let scheme: String?
    private let project: String?
    private let destination: String?

    public init(
        parallel: Bool = true,
        filter: String? = nil,
        scheme: String? = nil,
        project: String? = nil,
        destination: String? = nil
    ) {
        self.parallel = parallel
        self.filter = filter
        self.scheme = scheme
        self.project = project
        self.destination = destination
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        let command: String
        var args: [String]

        if let scheme {
            command = "xcodebuild"
            args = []
            if let project { args += ["-project", project] }
            args += ["-scheme", scheme, "test"]
            if let destination { args += ["-destination", destination] }
            if parallel { args += ["-parallel-testing-enabled", "YES"] }
            if let filter { args += ["-only-testing", filter] }
        } else {
            command = "swift"
            args = ["test"]
            if parallel {
                args.append("--parallel")
            }
            if let filter {
                args += ["--filter", filter]
            }
        }

        let output: String
        let exitCode: Int32

        if context.verbose {
            (output, exitCode) = try await Shell.runStreamingWithOutput(
                command,
                arguments: args,
                in: context.projectRoot,
                onOutput: verboseOutputHandler
            )
        } else {
            (output, exitCode) = try await Shell.runWithExitCode(
                command,
                arguments: args,
                in: context.projectRoot
            )
        }

        let duration = ContinuousClock.now - startTime

        if exitCode == 0 {
            return .passed(duration: duration)
        }

        let diagnostics = parseTestOutput(output)
        return .failed(diagnostics: diagnostics, duration: duration)
    }

    // MARK: - Verbose Output

    private func verboseOutputHandler(_ line: String, _ type: OutputType) {
        print("\(type.prefix) \(line)")
        fflush(stdout)
    }

    // MARK: - Private

    private func parseTestOutput(_ output: String) -> [HookDiagnostic] {
        // Look for test failures
        var diagnostics: [HookDiagnostic] = []

        for line in output.split(separator: "\n") {
            let str = String(line)

            // Match test failure lines
            if str.contains("failed") || str.contains("FAILED") {
                diagnostics.append(
                    HookDiagnostic(
                        message: str,
                        severity: .error
                    )
                )
            }
        }

        // If no specific failures found, add generic failure
        if diagnostics.isEmpty {
            diagnostics.append(
                HookDiagnostic(
                    message: "Tests failed. Run 'swift test' for details.",
                    severity: .error
                )
            )
        }

        return diagnostics
    }
}
