//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - TaskMode

/// Execution mode for a task within a stage
public enum TaskMode: String, Codable, Sendable, Equatable {
    /// Check only, no fixes applied
    case check

    /// Apply fixes then run check
    case fix

    /// Apply fixes only, skip the check (for quick pre-commit fixes)
    case fixOnly
}

// MARK: - StageTask

/// A task reference within a stage with per-stage configuration
public struct StageTask: Codable, Sendable, Equatable {
    /// Task identifier (matches HookTask.id)
    public let id: String

    /// Execution mode for this task in this stage
    public let mode: TaskMode

    /// Stage-specific options (merged with global TaskConfig.options)
    public let options: [String: AnyCodable]?

    public init(
        id: String,
        mode: TaskMode = .fix,
        options: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.mode = mode
        self.options = options
    }

    // Custom decoding to support shorthand format
    public init(from decoder: Decoder) throws {
        // Try string shorthand first: "format" or "format:check"
        if let container = try? decoder.singleValueContainer(),
            let stringValue = try? container.decode(String.self)
        {
            let parts = stringValue.split(separator: ":")
            guard let idPart = parts.first else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid task string format: empty string"
                )
            }
            id = String(idPart)

            if parts.count > 1 {
                let modeString = String(parts[1])
                guard let parsedMode = TaskMode(rawValue: modeString) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid task mode '\(modeString)' for task '\(id)'"
                    )
                }
                mode = parsedMode
            } else {
                mode = .fix
            }
            options = nil
            return
        }

        // Full object format
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mode = try container.decodeIfPresent(TaskMode.self, forKey: .mode) ?? .fix
        options = try container.decodeIfPresent([String: AnyCodable].self, forKey: .options)
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, options
    }
}

// MARK: - HookStage

/// A group of tasks that run together with optional dependencies on other stages
public struct HookStage: Codable, Sendable, Equatable {
    /// Unique name for this stage within the hook
    public let name: String

    /// Tasks to run in this stage
    public let tasks: [StageTask]

    /// Whether tasks in this stage run in parallel (default: true)
    public let parallel: Bool

    /// Names of other stages that must complete successfully before this one starts
    public let dependencies: [String]

    /// If true, continue to dependent stages even if this stage fails (default: false)
    public let continueOnError: Bool

    public init(
        name: String,
        tasks: [StageTask],
        parallel: Bool = true,
        dependencies: [String] = [],
        continueOnError: Bool = false
    ) {
        self.name = name
        self.tasks = tasks
        self.parallel = parallel
        self.dependencies = dependencies
        self.continueOnError = continueOnError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        tasks = try container.decode([StageTask].self, forKey: .tasks)
        parallel = try container.decodeIfPresent(Bool.self, forKey: .parallel) ?? true
        continueOnError = try container.decodeIfPresent(Bool.self, forKey: .continueOnError) ?? false

        // Handle both 'dependencies' (list) and 'dependsOn' (single string legacy)
        let explicitDependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        if let legacyDependency = try container.decodeIfPresent(String.self, forKey: .dependsOn) {
            dependencies = explicitDependencies + [legacyDependency]
        } else {
            dependencies = explicitDependencies
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(parallel, forKey: .parallel)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(continueOnError, forKey: .continueOnError)
    }

    private enum CodingKeys: String, CodingKey {
        case name, tasks, parallel, dependencies, dependsOn, continueOnError
    }

    private enum EncodingKeys: String, CodingKey {
        case name, tasks, parallel, dependencies, continueOnError
    }
}

// MARK: - StageResult

/// Result of executing a single stage
public struct StageResult: Sendable {
    /// Name of the stage
    public let stageName: String

    /// Results from all tasks in the stage
    public let taskResults: [TaskRunResult]

    /// Whether the stage succeeded (all blocking tasks passed)
    public let success: Bool

    /// Whether to continue to dependent stages even on failure
    public let continueOnError: Bool

    /// Total duration of the stage
    public let duration: Duration

    public init(
        stageName: String,
        taskResults: [TaskRunResult],
        success: Bool,
        continueOnError: Bool = false,
        duration: Duration = .zero
    ) {
        self.stageName = stageName
        self.taskResults = taskResults
        self.success = success
        self.continueOnError = continueOnError
        self.duration = duration
    }
}

// MARK: - HookError

/// Errors that can occur during hook execution
public enum HookError: Error, Sendable, CustomStringConvertible {
    /// A stage's dependency could not be satisfied
    case unsatisfiedDependency(stage: String, dependency: String)

    /// Circular dependency detected between stages
    case circularDependency([String])

    /// A stage failed and blocked dependent stages
    case stageBlocked(String)

    /// Unknown task referenced in configuration
    case unknownTask(String)

    /// Invalid task mode for the task type
    case invalidMode(task: String, mode: TaskMode)

    public var description: String {
        switch self {
        case .unsatisfiedDependency(let stage, let dependency):
            "Stage '\(stage)' depends on '\(dependency)' which does not exist"
        case .circularDependency(let stages):
            "Circular dependency detected: \(stages.joined(separator: " -> "))"
        case .stageBlocked(let stage):
            "Stage '\(stage)' failed and blocked subsequent stages"
        case .unknownTask(let task):
            "Unknown task '\(task)' referenced in configuration"
        case .invalidMode(let task, let mode):
            "Task '\(task)' does not support mode '\(mode.rawValue)'"
        }
    }
}

// MARK: - Default Stages

extension HookStage {
    /// Default pre-commit stages: autofix -> analysis -> validation
    public static let defaultPreCommit: [HookStage] = [
        HookStage(
            name: "autofix",
            tasks: [
                StageTask(id: "versionSync", mode: .fix),
                StageTask(id: "format", mode: .fix),
            ],
            parallel: true
        ),
        HookStage(
            name: "analysis",
            tasks: [
                StageTask(id: "unused", mode: .check),
                StageTask(id: "duplicates", mode: .check),
            ],
            parallel: true,
            dependencies: ["autofix"],
            continueOnError: true
        ),
        HookStage(
            name: "validation",
            tasks: [
                StageTask(id: "test", mode: .check)
            ],
            parallel: false,
            dependencies: ["analysis"]
        ),
    ]

    /// Default pre-push stages: verify only (no fixes)
    public static let defaultPrePush: [HookStage] = [
        HookStage(
            name: "verify",
            tasks: [
                StageTask(id: "versionSync", mode: .check),
                StageTask(id: "format", mode: .check),
            ],
            parallel: true
        )
    ]

    /// Default CI stages: quality -> test
    public static let defaultCI: [HookStage] = [
        HookStage(
            name: "quality",
            tasks: [
                StageTask(id: "format", mode: .check),
                StageTask(id: "unused", mode: .check),
                StageTask(id: "duplicates", mode: .check),
            ],
            parallel: true
        ),
        HookStage(
            name: "test",
            tasks: [
                StageTask(
                    id: "test",
                    mode: .check,
                    options: ["coverage": AnyCodable(true), "parallel": AnyCodable(true)]
                )
            ],
            parallel: false,
            dependencies: ["quality"]
        ),
    ]
}
