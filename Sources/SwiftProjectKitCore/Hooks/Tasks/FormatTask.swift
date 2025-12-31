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

// MARK: - FormatTask

/// Task that formats Swift code using swift-format.
///
/// This task can both check formatting (lint) and apply fixes.
/// It uses the pre-built swift-format binary for performance.
public struct FormatTask: HookTask {
    public let id = "format"
    public let name = "Format"
    public let hooks: Set<HookType> = [.preCommit, .ci]
    public let supportsFix = true
    public let fixSafety: FixSafety = .safe
    public let isBlocking = true
    public let filePatterns = ["**/*.swift"]

    private let paths: [String]
    private let excludePaths: [String]

    public init(
        paths: [String] = ["Sources/", "Tests/"],
        excludePaths: [String] = ["**/Fixtures/**"]
    ) {
        self.paths = paths
        self.excludePaths = excludePaths
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        // Get files to check based on scope
        let files = filesToCheck(context: context)
        guard !files.isEmpty else {
            return .skipped(reason: "No Swift files to check")
        }

        // Run swift-format lint
        var args = ["format", "lint", "--strict", "--parallel"]
        args += files

        let output: String
        let exitCode: Int32

        if context.verbose {
            (output, exitCode) = try await Shell.runStreamingWithOutput(
                "swift",
                arguments: args,
                in: context.projectRoot,
                onOutput: verboseOutputHandler
            )
        } else {
            (output, exitCode) = try await Shell.runWithExitCode(
                "swift",
                arguments: args,
                in: context.projectRoot
            )
        }

        let duration = ContinuousClock.now - startTime

        if exitCode == 0 {
            return .passed(duration: duration, filesChecked: files.count)
        }

        // Parse diagnostics from output
        let diagnostics = parseFormatOutput(output)

        return .failed(
            diagnostics: diagnostics,
            duration: duration,
            filesChecked: files.count,
            fixesAvailable: true
        )
    }

    public func fix(context: HookContext) async throws -> FixResult {
        let files = filesToCheck(context: context)
        guard !files.isEmpty else {
            return FixResult()
        }

        var args = ["format", "format", "--in-place", "--parallel"]
        args += files

        if context.verbose {
            _ = try await Shell.runStreaming(
                "swift",
                arguments: args,
                in: context.projectRoot,
                onOutput: verboseOutputHandler
            )
        } else {
            _ = try await Shell.run(
                "swift",
                arguments: args,
                in: context.projectRoot
            )
        }

        // Determine which files were actually modified
        // For simplicity, we'll return all files as potentially modified
        // In practice, we could compare checksums
        return FixResult(
            filesModified: files,
            fixesApplied: files.count
        )
    }

    // MARK: - Verbose Output

    private func verboseOutputHandler(_ line: String, _ type: OutputType) {
        print("\(type.prefix) \(line)")
        fflush(stdout)
    }

    // MARK: - Private

    private func filesToCheck(context: HookContext) -> [String] {
        switch context.scope {
        case .staged:
            context.stagedFiles
                .filter { isSwiftFile($0.path) && !isExcluded($0.path) }
                .map(\.path)
        case .changed, .diff:
            context.allFiles
                .filter { isSwiftFile($0) && !isExcluded($0) }
        case .all:
            paths.flatMap { path in
                findSwiftFiles(in: path, root: context.projectRoot)
            }
            .filter { !isExcluded($0) }
        }
    }

    private func isSwiftFile(_ path: String) -> Bool {
        path.hasSuffix(".swift")
    }

    private func isExcluded(_ path: String) -> Bool {
        for pattern in excludePaths {
            if matchesGlob(path, pattern: pattern) {
                return true
            }
        }
        return false
    }

    private func matchesGlob(_ path: String, pattern: String) -> Bool {
        // Simple glob matching for **/ patterns
        if pattern.hasPrefix("**/") {
            let suffix = String(pattern.dropFirst(3))
            return path.contains(suffix.replacingOccurrences(of: "**", with: ""))
        }
        return path.contains(pattern.replacingOccurrences(of: "*", with: ""))
    }

    private func findSwiftFiles(in path: String, root: URL) -> [String] {
        let url = root.appendingPathComponent(path)
        let fm = FileManager.default

        guard
            let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [String] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension == "swift" {
                let relativePath = fileURL.path.replacingOccurrences(
                    of: root.path + "/",
                    with: ""
                )
                files.append(relativePath)
            }
        }
        return files
    }

    private func parseFormatOutput(_ output: String) -> [HookDiagnostic] {
        // swift-format outputs lines like:
        // Sources/Foo.swift:10:5: warning: message
        // Using RegexBuilder for type-safe pattern matching
        let severityChoice = ChoiceOf {
            "warning"
            "error"
        }
        let formatPattern = Regex {
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
            guard let match = str.firstMatch(of: formatPattern) else {
                return nil
            }

            let file = String(match.1)
            let lineNum = Int(match.2) ?? 0
            let column = Int(match.3) ?? 0
            let severity: HookSeverity = match.4 == "error" ? .error : .warning
            let message = String(match.5)

            return HookDiagnostic(
                file: file,
                line: lineNum,
                column: column,
                message: message,
                severity: severity,
                ruleID: "format",
                fixable: true
            )
        }
    }
}
