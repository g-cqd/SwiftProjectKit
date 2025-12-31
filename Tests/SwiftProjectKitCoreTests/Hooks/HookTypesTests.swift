//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("HookTypes Tests")
struct HookTypesTests {

    // MARK: - HookType Tests

    @Test("HookType raw values")
    func hookTypeRawValues() {
        #expect(HookType.preCommit.rawValue == "pre-commit")
        #expect(HookType.prePush.rawValue == "pre-push")
        #expect(HookType.ci.rawValue == "ci")
    }

    // MARK: - HookScope Tests

    @Test("HookScope raw values")
    func hookScopeRawValues() {
        #expect(HookScope.staged.rawValue == "staged")
        #expect(HookScope.changed.rawValue == "changed")
        #expect(HookScope.all.rawValue == "all")
    }

    // MARK: - FixSafety Tests

    @Test("FixSafety raw values")
    func fixSafetyRawValues() {
        #expect(FixSafety.safe.rawValue == "safe")
        #expect(FixSafety.cautious.rawValue == "cautious")
        #expect(FixSafety.unsafe.rawValue == "unsafe")
    }

    // MARK: - HookDiagnostic Tests

    @Test("HookDiagnostic with all fields")
    func diagnosticAllFields() {
        let diagnostic = HookDiagnostic(
            file: "test.swift",
            line: 10,
            column: 5,
            message: "Test message",
            severity: .error,
            ruleID: "test-rule",
            fixable: true
        )

        #expect(diagnostic.file == "test.swift")
        #expect(diagnostic.line == 10)
        #expect(diagnostic.column == 5)
        #expect(diagnostic.message == "Test message")
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.ruleID == "test-rule")
        #expect(diagnostic.fixable == true)
    }

    @Test("HookDiagnostic with message only")
    func diagnosticMessageOnly() {
        let diagnostic = HookDiagnostic(message: "Simple error", severity: .warning)

        #expect(diagnostic.file == nil)
        #expect(diagnostic.line == nil)
        #expect(diagnostic.message == "Simple error")
        #expect(diagnostic.severity == .warning)
    }

    // MARK: - TaskResult Tests

    @Test("TaskResult.passed")
    func taskResultPassed() {
        let result = TaskResult.passed(duration: Duration.seconds(1))

        #expect(result.status == .passed)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("TaskResult.failed with diagnostics")
    func taskResultFailed() {
        let diagnostic = HookDiagnostic(message: "Error", severity: .error)
        let result = TaskResult.failed(diagnostics: [diagnostic])

        #expect(result.status == .failed)
        #expect(result.diagnostics.count == 1)
    }

    @Test("TaskResult.skipped")
    func taskResultSkipped() {
        let result = TaskResult.skipped(reason: "Not applicable")

        if case .skipped(let reason) = result.status {
            #expect(reason == "Not applicable")
        } else {
            Issue.record("Expected skipped status")
        }
    }

    // MARK: - FixResult Tests

    @Test("FixResult default values")
    func fixResultDefaults() {
        let result = FixResult()
        #expect(result.fixesApplied == 0)
        #expect(result.filesModified.isEmpty)
        #expect(result.errors.isEmpty)
        #expect(result.success == true)
    }

    @Test("FixResult with applied fixes")
    func fixResultWithFixes() {
        let result = FixResult(
            filesModified: ["file1.swift", "file2.swift"],
            fixesApplied: 5
        )
        #expect(result.fixesApplied == 5)
        #expect(result.filesModified.count == 2)
        #expect(result.success == true)
    }

    @Test("FixResult with errors")
    func fixResultWithErrors() {
        let result = FixResult(errors: ["Something went wrong"])
        #expect(result.success == false)
    }

    // MARK: - FixMode Tests

    @Test("FixMode.safe includes only safe fixes")
    func fixModeSafe() {
        #expect(FixMode.safe.includes(FixSafety.safe) == true)
        #expect(FixMode.safe.includes(FixSafety.cautious) == false)
        #expect(FixMode.safe.includes(FixSafety.unsafe) == false)
    }

    @Test("FixMode.cautious includes safe and cautious")
    func fixModeCautious() {
        #expect(FixMode.cautious.includes(FixSafety.safe) == true)
        #expect(FixMode.cautious.includes(FixSafety.cautious) == true)
        #expect(FixMode.cautious.includes(FixSafety.unsafe) == false)
    }

    @Test("FixMode.all includes everything")
    func fixModeAll() {
        #expect(FixMode.all.includes(FixSafety.safe) == true)
        #expect(FixMode.all.includes(FixSafety.cautious) == true)
        #expect(FixMode.all.includes(FixSafety.unsafe) == true)
    }

    @Test("FixMode.none includes nothing")
    func fixModeNone() {
        #expect(FixMode.none.includes(FixSafety.safe) == false)
        #expect(FixMode.none.includes(FixSafety.cautious) == false)
        #expect(FixMode.none.includes(FixSafety.unsafe) == false)
    }

    // MARK: - TaskStatus Tests

    @Test("TaskStatus passed")
    func taskStatusPassed() {
        let status = TaskStatus.passed
        #expect(status == .passed)
    }

    @Test("TaskStatus failed")
    func taskStatusFailed() {
        let status = TaskStatus.failed
        #expect(status == .failed)
    }

    @Test("TaskStatus skipped with reason")
    func taskStatusSkipped() {
        let status = TaskStatus.skipped(reason: "No files to check")
        if case .skipped(let reason) = status {
            #expect(reason == "No files to check")
        } else {
            Issue.record("Expected skipped status")
        }
    }
}
