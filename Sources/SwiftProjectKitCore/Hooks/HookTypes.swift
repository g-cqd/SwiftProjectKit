//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - HookType

/// The type of git hook being executed
public enum HookType: String, Codable, Sendable, CaseIterable {
    case preCommit = "pre-commit"
    case prePush = "pre-push"
    case ci
}

// MARK: - Scope

/// Defines which files a hook task should analyze
public enum HookScope: String, Codable, Sendable {
    /// Only files in the git staging area (index)
    case staged
    /// Files changed compared to base branch
    case changed
    /// Files changed in a PR (CI context)
    case diff
    /// Entire project
    case all
}

// MARK: - FixSafety

/// Classification of how safe an automatic fix is
public enum FixSafety: String, Codable, Sendable {
    /// Always safe: formatting, version sync
    case safe
    /// Usually safe: regex in markdown/docs
    case cautious
    /// Could break code: regex in .swift files
    case unsafe
}

// MARK: - Severity

/// Severity level for task diagnostics
public enum HookSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
}

// MARK: - TaskStatus

/// Result status of a hook task execution
public enum TaskStatus: Sendable, Equatable {
    case passed
    case failed
    case warning
    case skipped(reason: String)
}

// MARK: - HookDiagnostic

/// A diagnostic message from a hook task
public struct HookDiagnostic: Sendable {
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let message: String
    public let severity: HookSeverity
    public let ruleID: String?
    public let fixable: Bool

    public init(
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        message: String,
        severity: HookSeverity,
        ruleID: String? = nil,
        fixable: Bool = false
    ) {
        self.file = file
        self.line = line
        self.column = column
        self.message = message
        self.severity = severity
        self.ruleID = ruleID
        self.fixable = fixable
    }

    /// Format as Xcode-compatible diagnostic
    public var xcodeFormat: String {
        var location = ""
        if let file {
            location = file
            if let line {
                location += ":\(line)"
                if let column {
                    location += ":\(column)"
                }
            }
            location += ": "
        }
        return "\(location)\(severity.rawValue): \(message)"
    }
}

// MARK: - TaskResult

/// Result of running a hook task
public struct TaskResult: Sendable {
    public let status: TaskStatus
    public let diagnostics: [HookDiagnostic]
    public let duration: Duration
    public let filesChecked: Int
    public let fixesAvailable: Bool

    public init(
        status: TaskStatus,
        diagnostics: [HookDiagnostic] = [],
        duration: Duration = .zero,
        filesChecked: Int = 0,
        fixesAvailable: Bool = false
    ) {
        self.status = status
        self.diagnostics = diagnostics
        self.duration = duration
        self.filesChecked = filesChecked
        self.fixesAvailable = fixesAvailable
    }

    public static func passed(duration: Duration = .zero, filesChecked: Int = 0) -> Self {
        Self(status: .passed, duration: duration, filesChecked: filesChecked)
    }

    public static func failed(
        diagnostics: [HookDiagnostic],
        duration: Duration = .zero,
        filesChecked: Int = 0,
        fixesAvailable: Bool = false
    ) -> Self {
        Self(
            status: .failed,
            diagnostics: diagnostics,
            duration: duration,
            filesChecked: filesChecked,
            fixesAvailable: fixesAvailable
        )
    }

    public static func warning(
        diagnostics: [HookDiagnostic],
        duration: Duration = .zero,
        filesChecked: Int = 0
    ) -> Self {
        Self(status: .warning, diagnostics: diagnostics, duration: duration, filesChecked: filesChecked)
    }

    public static func skipped(reason: String) -> Self {
        Self(status: .skipped(reason: reason))
    }
}

// MARK: - FixResult

/// Result of applying fixes
public struct FixResult: Sendable {
    public let filesModified: [String]
    public let fixesApplied: Int
    public let errors: [String]

    public init(filesModified: [String] = [], fixesApplied: Int = 0, errors: [String] = []) {
        self.filesModified = filesModified
        self.fixesApplied = fixesApplied
        self.errors = errors
    }

    public var success: Bool {
        errors.isEmpty
    }
}

// MARK: - FixMode

/// How to handle automatic fixes
public enum FixMode: String, Codable, Sendable {
    /// Only apply safe fixes (default)
    case safe
    /// Apply safe and cautious fixes
    case cautious
    /// Apply all fixes including unsafe
    case all
    /// Don't apply any fixes (check only)
    case none

    /// Check if this mode includes fixes of the given safety level
    public func includes(_ safety: FixSafety) -> Bool {
        switch self {
        case .none:
            return false
        case .safe:
            return safety == .safe
        case .cautious:
            return safety == .safe || safety == .cautious
        case .all:
            return true
        }
    }
}
