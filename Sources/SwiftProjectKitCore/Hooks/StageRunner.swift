//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - StageRunner

/// Executes hook stages with dependency resolution and parallel execution.
///
/// The runner handles:
/// - Topological ordering of stages based on dependencies
/// - Parallel execution of independent stages
/// - Per-task mode handling (check, fix, fixOnly)
/// - Error propagation and blocking behavior
public actor StageRunner {
    private let projectRoot: URL
    private let config: HooksConfiguration
    private let registeredTasks: [String: any HookTask]
    private let output: HookOutput
    private let verbose: Bool

    public init(
        projectRoot: URL,
        config: HooksConfiguration,
        tasks: [any HookTask],
        output: HookOutput = ConsoleHookOutput(),
        verbose: Bool = false
    ) {
        self.projectRoot = projectRoot
        self.config = config
        self.output = output
        self.verbose = verbose

        var taskMap: [String: any HookTask] = [:]
        for task in tasks {
            taskMap[task.id] = task
        }
        registeredTasks = taskMap
    }

    // MARK: - Public API

    /// Run all stages for a hook type
    ///
    /// Stages are executed in dependency order. Stages with satisfied dependencies
    /// can run in parallel. Within each stage, tasks run according to the stage's
    /// `parallel` setting.
    ///
    /// - Parameters:
    ///   - stages: The stages to execute
    ///   - context: The hook execution context
    /// - Returns: Results from all stages
    /// - Throws: `HookError` if dependencies cannot be satisfied
    public func runStages(
        _ stages: [HookStage],
        context: HookContext
    ) async throws -> [StageResult] {
        guard !stages.isEmpty else { return [] }

        // Validate dependencies
        try validateDependencies(stages)

        var completed: [String: StageResult] = [:]
        var pending = stages

        while !pending.isEmpty {
            // Find stages whose dependencies are all satisfied
            let ready = pending.filter { stage in
                // No dependencies means ready to run
                guard !stage.dependencies.isEmpty else { return true }

                // All dependencies must be completed
                return stage.dependencies.allSatisfy { dep in
                    guard let depResult = completed[dep] else { return false }
                    // Can proceed if dependency succeeded or stage allows continue on error
                    return depResult.success || stage.continueOnError
                }
            }

            guard !ready.isEmpty else {
                // All remaining stages are blocked - find the cause
                let blocked = pending.map(\.name)
                let failedDeps = pending.flatMap { stage in
                    stage.dependencies.compactMap { dep in
                        if let result = completed[dep], !result.success {
                            return dep
                        }
                        return nil
                    }
                }
                if let firstFailed = failedDeps.first {
                    throw HookError.stageBlocked(firstFailed)
                }
                throw HookError.stageBlocked(blocked.first ?? "unknown")
            }

            // Execute ready stages
            let results: [StageResult]
            if ready.count > 1 {
                // Multiple stages ready - run in parallel
                results = await withTaskGroup(of: StageResult.self) { group in
                    for stage in ready {
                        group.addTask {
                            await self.runStage(stage, context: context)
                        }
                    }

                    var stageResults: [StageResult] = []
                    for await result in group {
                        stageResults.append(result)
                    }
                    return stageResults
                }
            } else {
                // Single stage
                let result = await runStage(ready[0], context: context)
                results = [result]
            }

            // Record results
            for result in results {
                completed[result.stageName] = result
            }

            // Remove completed stages from pending
            let readyNames = Set(ready.map(\.name))
            pending.removeAll { readyNames.contains($0.name) }

            // Check for blocking failures
            for result in results {
                if !result.success && !result.continueOnError {
                    // Check if any pending stages depend on this
                    let blocked = pending.filter { $0.dependencies.contains(result.stageName) }
                    if !blocked.isEmpty {
                        await output.warning(
                            "Stage '\(result.stageName)' failed, blocking: \(blocked.map(\.name).joined(separator: ", "))"
                        )
                    }
                }
            }
        }

        return Array(completed.values)
    }

    // MARK: - Stage Execution

    private func runStage(
        _ stage: HookStage,
        context: HookContext
    ) async -> StageResult {
        let startTime = ContinuousClock.now

        await output.header("Stage: \(stage.name)")

        // Check for unknown tasks first (fail fast on configuration errors)
        let unknownTasks = stage.tasks.filter { registeredTasks[$0.id] == nil }
        if !unknownTasks.isEmpty {
            for unknown in unknownTasks {
                await output.warning("Configuration error: Task '\(unknown.id)' not found in registry")
            }

            // Return failed result for configuration errors
            let diagnostics = unknownTasks.map { stageTask in
                HookDiagnostic(
                    message: "Unknown task '\(stageTask.id)' - check your configuration",
                    severity: .error
                )
            }

            return StageResult(
                stageName: stage.name,
                taskResults: [
                    TaskRunResult(
                        taskID: "configuration",
                        taskResult: .failed(diagnostics: diagnostics),
                        fixResult: nil,
                        isBlocking: true
                    )
                ],
                success: false,
                continueOnError: stage.continueOnError,
                duration: ContinuousClock.now - startTime
            )
        }

        // Resolve tasks (now guaranteed to exist)
        let resolvedTasks: [(task: any HookTask, mode: TaskMode, options: [String: AnyCodable]?)] =
            stage.tasks.compactMap { stageTask in
                guard let task = registeredTasks[stageTask.id] else { return nil }
                return (task, stageTask.mode, stageTask.options)
            }

        guard !resolvedTasks.isEmpty else {
            return StageResult(
                stageName: stage.name,
                taskResults: [],
                success: true,
                continueOnError: stage.continueOnError,
                duration: ContinuousClock.now - startTime
            )
        }

        // Execute tasks
        let taskResults: [TaskRunResult]
        if stage.parallel {
            taskResults = await runTasksInParallel(resolvedTasks, context: context)
        } else {
            taskResults = await runTasksSequentially(resolvedTasks, context: context)
        }

        // Determine success
        let success = taskResults.allSatisfy { result in
            switch result.taskResult.status {
            case .passed, .warning, .skipped:
                true
            case .failed:
                !result.isBlocking
            }
        }

        let duration = ContinuousClock.now - startTime

        // Report stage result
        if success {
            await output.info("Stage '\(stage.name)' completed successfully")
        } else {
            await output.warning("Stage '\(stage.name)' failed")
        }

        return StageResult(
            stageName: stage.name,
            taskResults: taskResults,
            success: success,
            continueOnError: stage.continueOnError,
            duration: duration
        )
    }

    // MARK: - Task Execution

    private func runTasksInParallel(
        _ tasks: [(task: any HookTask, mode: TaskMode, options: [String: AnyCodable]?)],
        context: HookContext
    ) async -> [TaskRunResult] {
        await withTaskGroup(of: TaskRunResult.self) { group in
            for (task, mode, options) in tasks {
                group.addTask {
                    await self.runSingleTask(task, mode: mode, options: options, context: context)
                }
            }

            var results: [TaskRunResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func runTasksSequentially(
        _ tasks: [(task: any HookTask, mode: TaskMode, options: [String: AnyCodable]?)],
        context: HookContext
    ) async -> [TaskRunResult] {
        var results: [TaskRunResult] = []
        for (task, mode, options) in tasks {
            let result = await runSingleTask(task, mode: mode, options: options, context: context)
            results.append(result)

            // Fail fast if configured
            if config.failFast {
                if case .failed = result.taskResult.status, result.isBlocking {
                    break
                }
            }
        }
        return results
    }

    private func runSingleTask(
        _ task: any HookTask,
        mode: TaskMode,
        options: [String: AnyCodable]?,
        context: HookContext
    ) async -> TaskRunResult {
        let taskConfig = config.tasks[task.id]
        let isBlocking = taskConfig?.blocking ?? task.isBlocking

        await output.taskStart(task.name)
        let startTime = ContinuousClock.now

        // Create context with mode-appropriate fix mode
        let effectiveFixMode: FixMode =
            switch mode {
            case .check:
                .none
            case .fix, .fixOnly:
                context.fixMode
            }

        let taskContext = HookContext(
            projectRoot: context.projectRoot,
            scope: context.scope,
            stagedFiles: context.stagedFiles,
            allFiles: context.allFiles,
            config: context.config,
            isCI: context.isCI,
            hookType: context.hookType,
            fixMode: effectiveFixMode,
            gitIndex: context.gitIndex,
            verbose: context.verbose
        )

        do {
            var fixResult: FixResult?

            // Apply fixes if mode allows
            if mode == .fix || mode == .fixOnly {
                if task.supportsFix, taskContext.canFix(safety: task.fixSafety) {
                    fixResult = try await task.fix(context: taskContext)
                }
            }

            // Run check unless fixOnly mode
            let taskResult: TaskResult
            if mode == .fixOnly {
                // Skip check, report fix result
                if let fixResult, !fixResult.filesModified.isEmpty {
                    taskResult = .passed(
                        duration: ContinuousClock.now - startTime,
                        filesChecked: fixResult.filesModified.count
                    )
                } else {
                    taskResult = .passed(duration: ContinuousClock.now - startTime)
                }
            } else {
                taskResult = try await task.run(context: taskContext)
            }

            let duration = ContinuousClock.now - startTime

            await output.taskComplete(
                task.name,
                status: taskResult.status,
                duration: duration,
                message: formatResultMessage(taskResult, fixResult: fixResult, mode: mode)
            )

            return TaskRunResult(
                taskID: task.id,
                taskResult: taskResult,
                fixResult: fixResult,
                isBlocking: isBlocking
            )
        } catch {
            let duration = ContinuousClock.now - startTime
            await output.taskComplete(
                task.name,
                status: .failed,
                duration: duration,
                message: error.localizedDescription
            )

            return TaskRunResult(
                taskID: task.id,
                taskResult: TaskResult.failed(
                    diagnostics: [
                        HookDiagnostic(
                            message: error.localizedDescription,
                            severity: .error
                        )
                    ]
                ),
                fixResult: nil,
                isBlocking: isBlocking
            )
        }
    }

    // MARK: - Validation

    private func validateDependencies(_ stages: [HookStage]) throws {
        let stageNames = Set(stages.map(\.name))

        // Check all dependencies exist
        for stage in stages {
            for dep in stage.dependencies where !stageNames.contains(dep) {
                throw HookError.unsatisfiedDependency(stage: stage.name, dependency: dep)
            }
        }

        // Check for cycles using DFS
        var visited: Set<String> = []
        var path: [String] = []

        func visit(_ name: String) throws {
            if path.contains(name) {
                let cycleStart = path.firstIndex(of: name) ?? 0
                throw HookError.circularDependency(Array(path[cycleStart...]) + [name])
            }
            if visited.contains(name) { return }

            path.append(name)
            if let stage = stages.first(where: { $0.name == name }) {
                for dep in stage.dependencies {
                    try visit(dep)
                }
            }
            path.removeLast()
            visited.insert(name)
        }

        for stage in stages {
            try visit(stage.name)
        }
    }

    // MARK: - Formatting

    private func formatResultMessage(
        _ result: TaskResult,
        fixResult: FixResult?,
        mode: TaskMode
    ) -> String? {
        var parts: [String] = []

        // Mode indicator
        switch mode {
        case .check:
            break  // Default, no indicator needed
        case .fix:
            if let fixResult, !fixResult.filesModified.isEmpty {
                parts.append("fixed \(fixResult.filesModified.count) file(s)")
            }
        case .fixOnly:
            if let fixResult, !fixResult.filesModified.isEmpty {
                parts.append("fixed \(fixResult.filesModified.count) file(s)")
            } else {
                parts.append("no changes needed")
            }
        }

        if result.filesChecked > 0, mode != .fixOnly {
            parts.append("\(result.filesChecked) file(s) checked")
        }

        if !result.diagnostics.isEmpty {
            let errors = result.diagnostics.filter { $0.severity == .error }.count
            let warnings = result.diagnostics.filter { $0.severity == .warning }.count
            if errors > 0 { parts.append("\(errors) error(s)") }
            if warnings > 0 { parts.append("\(warnings) warning(s)") }
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
