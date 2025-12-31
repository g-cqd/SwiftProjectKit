//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - HookTask

/// Protocol for tasks that can be run as part of git hooks.
///
/// Implementations should be lightweight and stateless. All state
/// is passed through `HookContext`.
///
/// ## Thread Safety
///
/// All hook tasks must be `Sendable` as they may run in parallel.
///
/// ## Example
///
/// ```swift
/// struct FormatTask: HookTask {
///     let id = "format"
///     let name = "Format"
///     let hooks: Set<HookType> = [.preCommit, .ci]
///     let supportsFix = true
///     let fixSafety: FixSafety = .safe
///     let isBlocking = true
///
///     func run(context: HookContext) async throws -> TaskResult { ... }
///     func fix(context: HookContext) async throws -> FixResult { ... }
/// }
/// ```
public protocol HookTask: Sendable {
    /// Unique identifier for this task (used in configuration)
    var id: String { get }

    /// Human-readable name for output
    var name: String { get }

    /// Which hooks this task runs on by default
    var hooks: Set<HookType> { get }

    /// Whether this task can automatically fix issues
    var supportsFix: Bool { get }

    /// How safe the automatic fix is
    var fixSafety: FixSafety { get }

    /// Whether failure of this task blocks the commit
    var isBlocking: Bool { get }

    /// File patterns this task operates on (for change detection)
    var filePatterns: [String] { get }

    /// Run the check
    ///
    /// - Parameter context: The hook execution context
    /// - Returns: Result of the check
    func run(context: HookContext) async throws -> TaskResult

    /// Apply automatic fixes
    ///
    /// Only called if `supportsFix` is `true` and fix mode allows it.
    ///
    /// - Parameter context: The hook execution context
    /// - Returns: Result of the fix operation
    func fix(context: HookContext) async throws -> FixResult
}

// MARK: - Default Implementations

extension HookTask {
    public var filePatterns: [String] {
        ["**/*.swift"]
    }

    public func fix(context: HookContext) async throws -> FixResult {
        FixResult()
    }
}

// MARK: - HookContext

/// Context passed to hook tasks during execution.
///
/// Contains all information needed to run a task including
/// the project root, files to check, and configuration.
public struct HookContext: Sendable {
    /// Root directory of the project
    public let projectRoot: URL

    /// The scope of files to analyze
    public let scope: HookScope

    /// Files in the staging area (if scope is .staged)
    public let stagedFiles: [StagedFile]

    /// All files matching the task's patterns in the project
    public let allFiles: [String]

    /// Hooks configuration
    public let config: HooksConfiguration

    /// Whether running in CI environment
    public let isCI: Bool

    /// The current hook type being executed
    public let hookType: HookType

    /// The fix mode to use
    public let fixMode: FixMode

    /// Git index for reading staged content
    public let gitIndex: GitIndex

    /// Whether to output verbose information (stream process output)
    public let verbose: Bool

    public init(
        projectRoot: URL,
        scope: HookScope,
        stagedFiles: [StagedFile] = [],
        allFiles: [String] = [],
        config: HooksConfiguration,
        isCI: Bool = false,
        hookType: HookType,
        fixMode: FixMode = .safe,
        gitIndex: GitIndex,
        verbose: Bool = false
    ) {
        self.projectRoot = projectRoot
        self.scope = scope
        self.stagedFiles = stagedFiles
        self.allFiles = allFiles
        self.config = config
        self.isCI = isCI
        self.hookType = hookType
        self.fixMode = fixMode
        self.gitIndex = gitIndex
        self.verbose = verbose
    }

    /// Get the files to check based on scope
    public var filesToCheck: [String] {
        switch scope {
        case .staged:
            stagedFiles.map(\.path)
        case .changed, .diff:
            allFiles
        case .all:
            allFiles
        }
    }

    /// Check if a fix safety level is allowed by current fix mode
    public func canFix(safety: FixSafety) -> Bool {
        switch fixMode {
        case .none:
            false
        case .safe:
            safety == .safe
        case .cautious:
            safety == .safe || safety == .cautious
        case .all:
            true
        }
    }
}

// MARK: - StagedFile

/// A file in the git staging area
public struct StagedFile: Sendable {
    /// Path relative to project root
    public let path: String

    /// The git status of the file
    public let status: FileStatus

    /// Reference to git index for reading content
    private let gitIndex: GitIndex

    public init(path: String, status: FileStatus, gitIndex: GitIndex) {
        self.path = path
        self.status = status
        self.gitIndex = gitIndex
    }

    /// Read the staged content (from git index, not working directory)
    public func stagedContent() async throws -> String {
        try await gitIndex.stagedContent(of: path)
    }

    public enum FileStatus: String, Sendable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case untracked = "?"
    }
}
