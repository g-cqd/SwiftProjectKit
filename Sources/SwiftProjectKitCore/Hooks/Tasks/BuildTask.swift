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

    public init(configuration: String = "debug") {
        self.configuration = configuration
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        let args = ["build", "-c", configuration]

        let (output, exitCode) = try await Shell.runWithExitCode(
            "swift",
            arguments: args,
            in: context.projectRoot
        )

        let duration = ContinuousClock.now - startTime

        if exitCode == 0 {
            return .passed(duration: duration)
        }

        let diagnostics = parseBuildOutput(output)
        return .failed(diagnostics: diagnostics, duration: duration)
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

    public init(parallel: Bool = true, filter: String? = nil) {
        self.parallel = parallel
        self.filter = filter
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        var args = ["test"]
        if parallel {
            args.append("--parallel")
        }
        if let filter {
            args += ["--filter", filter]
        }

        let (output, exitCode) = try await Shell.runWithExitCode(
            "swift",
            arguments: args,
            in: context.projectRoot
        )

        let duration = ContinuousClock.now - startTime

        if exitCode == 0 {
            return .passed(duration: duration)
        }

        let diagnostics = parseTestOutput(output)
        return .failed(diagnostics: diagnostics, duration: duration)
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
