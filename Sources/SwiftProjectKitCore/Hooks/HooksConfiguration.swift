//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - HooksConfiguration

/// Configuration for the hooks system.
///
/// This is loaded from the `hooks` section of `.spk.json`.
public struct HooksConfiguration: Codable, Sendable, Equatable {
    /// Global fix mode (can be overridden per-task)
    public var fixMode: FixMode

    /// Whether to automatically restage fixed files
    public var restageFixed: Bool

    /// Whether to fail fast on first error
    public var failFast: Bool

    /// Pre-commit hook configuration
    public var preCommit: HookStageConfig

    /// Pre-push hook configuration
    public var prePush: HookStageConfig

    /// CI hook configuration
    public var ci: HookStageConfig

    /// Task-specific configurations
    public var tasks: [String: TaskConfig]

    public init(
        fixMode: FixMode = .safe,
        restageFixed: Bool = true,
        failFast: Bool = false,
        preCommit: HookStageConfig = .defaultPreCommit,
        prePush: HookStageConfig = .defaultPrePush,
        ci: HookStageConfig = .defaultCI,
        tasks: [String: TaskConfig] = [:]
    ) {
        self.fixMode = fixMode
        self.restageFixed = restageFixed
        self.failFast = failFast
        self.preCommit = preCommit
        self.prePush = prePush
        self.ci = ci
        self.tasks = tasks
    }

    public static let `default` = Self()
}

// MARK: - HookStageConfig

/// Configuration for a specific hook stage (pre-commit, pre-push, ci)
public struct HookStageConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var scope: HookScope
    public var baseBranch: String?
    public var parallel: Bool
    public var tasks: [String]

    public init(
        enabled: Bool = true,
        scope: HookScope = .all,
        baseBranch: String? = nil,
        parallel: Bool = true,
        tasks: [String] = []
    ) {
        self.enabled = enabled
        self.scope = scope
        self.baseBranch = baseBranch
        self.parallel = parallel
        self.tasks = tasks
    }

    public static let defaultPreCommit = Self(
        enabled: true,
        scope: .staged,
        parallel: true,
        tasks: ["format", "versionSync", "build"]
    )

    public static let defaultPrePush = Self(
        enabled: true,
        scope: .changed,
        baseBranch: "main",
        parallel: true,
        tasks: ["test"]
    )

    public static let defaultCI = Self(
        enabled: true,
        scope: .all,
        parallel: true,
        tasks: ["format:check", "versionSync:check", "build", "test"]
    )
}

// MARK: - TaskConfig

/// Configuration for a specific task
public struct TaskConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var blocking: Bool
    public var fixSafety: FixSafety?
    public var paths: [String]?
    public var excludePaths: [String]?

    // Task-specific options
    public var options: [String: AnyCodable]?

    public init(
        enabled: Bool = true,
        blocking: Bool = true,
        fixSafety: FixSafety? = nil,
        paths: [String]? = nil,
        excludePaths: [String]? = nil,
        options: [String: AnyCodable]? = nil
    ) {
        self.enabled = enabled
        self.blocking = blocking
        self.fixSafety = fixSafety
        self.paths = paths
        self.excludePaths = excludePaths
        self.options = options
    }
}

// MARK: - AnyCodable

/// Type-erased codable value for flexible configuration
public struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = ()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
