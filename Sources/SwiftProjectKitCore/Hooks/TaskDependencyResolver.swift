//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - TaskSpec

/// Specification for a task in a hook configuration
public struct TaskSpec: Codable, Sendable, Equatable {
    /// Task identifier (matches HookTask.id)
    public let id: String

    /// Execution mode for this task
    public let mode: TaskMode

    /// Task IDs that must complete before this task runs
    public let dependsOn: [String]

    /// Stage-specific options
    public let options: [String: AnyCodable]?

    /// Whether this task blocks the hook on failure (overrides task default)
    public let blocking: Bool?

    /// Whether to continue even if this task fails
    public let continueOnError: Bool

    public init(
        id: String,
        mode: TaskMode = .fix,
        dependsOn: [String] = [],
        options: [String: AnyCodable]? = nil,
        blocking: Bool? = nil,
        continueOnError: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.dependsOn = dependsOn
        self.options = options
        self.blocking = blocking
        self.continueOnError = continueOnError
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
            dependsOn = []
            options = nil
            blocking = nil
            continueOnError = false
            return
        }

        // Full object format
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mode = try container.decodeIfPresent(TaskMode.self, forKey: .mode) ?? .fix
        dependsOn = try container.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        options = try container.decodeIfPresent([String: AnyCodable].self, forKey: .options)
        blocking = try container.decodeIfPresent(Bool.self, forKey: .blocking)
        continueOnError = try container.decodeIfPresent(Bool.self, forKey: .continueOnError) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, dependsOn, options, blocking, continueOnError
    }
}

// MARK: - TaskDependencyResolver

/// Resolves task dependencies and computes execution order.
///
/// When `parallel` is true, tasks are grouped into waves where each wave
/// contains tasks whose dependencies are all satisfied by previous waves.
/// Tasks within a wave can run concurrently.
///
/// When `parallel` is false, tasks run sequentially in definition order.
public enum TaskDependencyResolver {

    /// Result of dependency resolution
    public struct Resolution: Sendable {
        /// Tasks grouped into execution waves (for parallel execution)
        public let waves: [[TaskSpec]]

        /// Whether execution should be parallel
        public let parallel: Bool

        /// All tasks in execution order (flattened waves)
        public var allTasks: [TaskSpec] {
            waves.flatMap { $0 }
        }
    }

    /// Resolve task dependencies and compute execution order
    ///
    /// - Parameters:
    ///   - tasks: Task specifications with dependencies
    ///   - parallel: Whether to group independent tasks for parallel execution
    /// - Returns: Resolution with tasks grouped into execution waves
    /// - Throws: `DependencyError` if dependencies cannot be satisfied
    public static func resolve(
        tasks: [TaskSpec],
        parallel: Bool
    ) throws -> Resolution {
        guard !tasks.isEmpty else {
            return Resolution(waves: [], parallel: parallel)
        }

        // Build task lookup
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Validate dependencies exist
        for task in tasks {
            for dep in task.dependsOn where taskMap[dep] == nil {
                throw DependencyError.missingDependency(task: task.id, dependency: dep)
            }
        }

        // Check for cycles
        try detectCycles(in: tasks)

        guard parallel else {
            // Sequential: each task is its own wave, in definition order
            return Resolution(waves: tasks.map { [$0] }, parallel: false)
        }
        // Group into waves based on dependencies
        return Resolution(waves: computeWaves(tasks: tasks), parallel: true)
    }

    /// Convert resolution to HookStages for compatibility with StageRunner
    public static func toStages(_ resolution: Resolution) -> [HookStage] {
        resolution.waves.enumerated().map { index, wave in
            let stageTasks = wave.map { spec in
                StageTask(id: spec.id, mode: spec.mode, options: spec.options)
            }

            // Depend on the previous wave's stage name (not task IDs)
            let dependencies: [String]
            if index > 0 {
                dependencies = ["wave-\(index)"]  // Previous wave's name
            } else {
                dependencies = []
            }

            // continueOnError if any task in wave has it
            let continueOnError = wave.contains { $0.continueOnError }

            return HookStage(
                name: "wave-\(index + 1)",
                tasks: stageTasks,
                parallel: resolution.parallel,
                dependencies: dependencies,
                continueOnError: continueOnError
            )
        }
    }

    // MARK: - Private

    private static func computeWaves(tasks: [TaskSpec]) -> [[TaskSpec]] {
        var waves: [[TaskSpec]] = []
        var completed: Set<String> = []
        var remaining = tasks

        while !remaining.isEmpty {
            // Find tasks whose dependencies are all completed
            let ready = remaining.filter { task in
                task.dependsOn.allSatisfy { completed.contains($0) }
            }

            guard !ready.isEmpty else {
                // This shouldn't happen if cycle detection worked
                fatalError("Dependency resolution stuck - possible undetected cycle")
            }

            waves.append(ready)
            completed.formUnion(ready.map(\.id))
            remaining.removeAll { ready.map(\.id).contains($0.id) }
        }

        return waves
    }

    private static func detectCycles(in tasks: [TaskSpec]) throws {
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var visited: Set<String> = []
        var path: [String] = []

        func visit(_ id: String) throws {
            if path.contains(id) {
                let cycleStart = path.firstIndex(of: id) ?? 0
                throw DependencyError.circularDependency(Array(path[cycleStart...]) + [id])
            }
            if visited.contains(id) { return }

            path.append(id)
            if let task = taskMap[id] {
                for dep in task.dependsOn {
                    try visit(dep)
                }
            }
            path.removeLast()
            visited.insert(id)
        }

        for task in tasks {
            try visit(task.id)
        }
    }
}

// MARK: - DependencyError

/// Errors that can occur during dependency resolution
public enum DependencyError: Error, Sendable, CustomStringConvertible {
    /// A task depends on another task that doesn't exist
    case missingDependency(task: String, dependency: String)

    /// Circular dependency detected
    case circularDependency([String])

    public var description: String {
        switch self {
        case .missingDependency(let task, let dependency):
            "Task '\(task)' depends on '\(dependency)' which does not exist"
        case .circularDependency(let tasks):
            "Circular dependency detected: \(tasks.joined(separator: " -> "))"
        }
    }
}
