//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - HookRunner

/// Orchestrates the execution of hook tasks.
///
/// The runner is responsible for:
/// - Loading configuration
/// - Resolving which tasks to run
/// - Executing tasks (optionally in parallel)
/// - Applying fixes and restaging
/// - Reporting results
public actor HookRunner {
    private let projectRoot: URL
    private let config: HooksConfiguration
    private let gitIndex: GitIndex
    private let registeredTasks: [String: any HookTask]
    private let output: HookOutput
    private let verbose: Bool

    public init(
        projectRoot: URL,
        config: HooksConfiguration,
        tasks: [any HookTask] = [],
        output: HookOutput = ConsoleHookOutput(),
        verbose: Bool = false
    ) {
        self.projectRoot = projectRoot
        self.config = config
        gitIndex = GitIndex(projectRoot: projectRoot)
        self.output = output
        self.verbose = verbose

        // Register tasks by ID
        var taskMap: [String: any HookTask] = [:]
        for task in tasks {
            taskMap[task.id] = task
        }
        registeredTasks = taskMap
    }

    // MARK: - Public API

    /// Run all tasks for a specific hook type
    ///
    /// When the hook configuration uses the new `stages` format, tasks are executed
    /// in dependency order using the `StageRunner`. Otherwise, falls back to legacy
    /// flat task execution.
    public func run(
        hook: HookType,
        fixMode: FixMode? = nil
    ) async throws -> HookRunResult {
        let hookStageConfig = stageConfig(for: hook)

        guard hookStageConfig.enabled else {
            await output.info("Hook '\(hook.rawValue)' is disabled")
            return HookRunResult(success: true, results: [])
        }

        await output.header("Running \(hook.rawValue) hooks...")

        // Build context
        let context = try await buildContext(
            hook: hook,
            scope: hookStageConfig.scope,
            fixMode: fixMode ?? config.fixMode
        )

        // Use stage-based execution if stages are configured
        let stages = hookStageConfig.resolvedStages
        guard !stages.isEmpty else {
            await output.warning("No tasks configured for \(hook.rawValue)")
            return HookRunResult(success: true, results: [])
        }

        // Create stage runner and execute
        let stageRunner = StageRunner(
            projectRoot: projectRoot,
            config: config,
            tasks: Array(registeredTasks.values),
            output: output,
            verbose: verbose
        )

        let stageResults = try await stageRunner.runStages(stages, context: context)

        // Collect all task results from stages
        let results = stageResults.flatMap(\.taskResults)

        // Restage fixed files if needed
        if config.restageFixed {
            let fixedFiles = results.flatMap { $0.fixResult?.filesModified ?? [] }
            if !fixedFiles.isEmpty {
                try await gitIndex.restage(files: fixedFiles)
                await output.info("Restaged \(fixedFiles.count) fixed file(s)")
            }
        }

        // Report results
        await reportResults(results)

        // Success if all stages succeeded
        let success = stageResults.allSatisfy(\.success)

        return HookRunResult(success: success, results: results)
    }

    /// Run only fix operations for all fixable tasks
    public func fix(fixMode: FixMode = .safe) async throws -> [FixResult] {
        await output.header("Applying fixes...")

        let allTasks = registeredTasks.values.filter { $0.supportsFix }
        let context = try await buildContext(
            hook: .preCommit,
            scope: .all,
            fixMode: fixMode
        )

        var results: [FixResult] = []

        for task in allTasks {
            guard context.canFix(safety: task.fixSafety) else {
                continue
            }

            await output.taskStart(task.name)
            do {
                let result = try await task.fix(context: context)
                results.append(result)
                if !result.filesModified.isEmpty {
                    await output.taskComplete(
                        task.name,
                        status: .passed,
                        message: "Fixed \(result.filesModified.count) file(s)"
                    )
                } else {
                    await output.taskComplete(task.name, status: .passed, message: nil)
                }
            } catch {
                await output.taskComplete(task.name, status: .failed, message: error.localizedDescription)
            }
        }

        // Restage
        let allFixed = results.flatMap(\.filesModified)
        if !allFixed.isEmpty, config.restageFixed {
            try await gitIndex.restage(files: allFixed)
            await output.info("Restaged \(allFixed.count) file(s)")
        }

        return results
    }

    // MARK: - Private Helpers

    private func stageConfig(for hook: HookType) -> HookStageConfig {
        switch hook {
        case .preCommit: config.preCommit
        case .prePush: config.prePush
        case .ci: config.ci
        }
    }

    private func resolveTask(id: String) -> (any HookTask)? {
        // Handle modifiers like "format:check"
        let baseID = id.split(separator: ":").first.map(String.init) ?? id
        return registeredTasks[baseID]
    }

    private func buildContext(
        hook: HookType,
        scope: HookScope,
        fixMode: FixMode
    ) async throws -> HookContext {
        let stagedFiles: [StagedFile]
        let allFiles: [String]

        switch scope {
        case .staged:
            stagedFiles = try await gitIndex.stagedFiles()
            allFiles = []
        case .changed:
            stagedFiles = []
            allFiles = try await gitIndex.changedFilesVsOrigin()
        case .diff:
            stagedFiles = []
            // In CI, would need to be passed in
            allFiles = try await gitIndex.changedFilesVsOrigin()
        case .all:
            stagedFiles = []
            allFiles = try await findAllSwiftFiles()
        }

        return HookContext(
            projectRoot: projectRoot,
            scope: scope,
            stagedFiles: stagedFiles,
            allFiles: allFiles,
            config: config,
            isCI: hook == .ci,
            hookType: hook,
            fixMode: fixMode,
            gitIndex: gitIndex,
            verbose: verbose
        )
    }

    private func findAllSwiftFiles() async throws -> [String] {
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" {
                let relativePath = url.path.replacingOccurrences(
                    of: projectRoot.path + "/",
                    with: ""
                )
                files.append(relativePath)
            }
        }
        return files
    }

    private func runTasksInParallel(
        _ tasks: [any HookTask],
        context: HookContext
    ) async -> [TaskRunResult] {
        await withTaskGroup(of: TaskRunResult.self) { group in
            for task in tasks {
                group.addTask {
                    await self.runSingleTask(task, context: context)
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
        _ tasks: [any HookTask],
        context: HookContext
    ) async -> [TaskRunResult] {
        var results: [TaskRunResult] = []
        for task in tasks {
            let result = await runSingleTask(task, context: context)
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
        context: HookContext
    ) async -> TaskRunResult {
        let taskConfig = config.tasks[task.id]
        let isBlocking = taskConfig?.blocking ?? task.isBlocking

        await output.taskStart(task.name)
        let startTime = ContinuousClock.now

        do {
            // Apply fix first if enabled
            var fixResult: FixResult?
            if task.supportsFix, context.canFix(safety: task.fixSafety) {
                fixResult = try await task.fix(context: context)
            }

            // Then run the check
            let taskResult = try await task.run(context: context)
            let duration = ContinuousClock.now - startTime

            let status: TaskStatus
            switch taskResult.status {
            case .passed:
                status = .passed
            case .failed:
                status = .failed
            case .warning:
                status = .warning
            case .skipped(let reason):
                status = .skipped(reason: reason)
            }

            await output.taskComplete(
                task.name,
                status: status,
                duration: duration,
                message: formatResultMessage(taskResult, fixResult: fixResult)
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

    private func formatResultMessage(_ result: TaskResult, fixResult: FixResult?) -> String? {
        var parts: [String] = []

        if let fixResult, !fixResult.filesModified.isEmpty {
            parts.append("fixed \(fixResult.filesModified.count) file(s)")
        }

        if result.filesChecked > 0 {
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

    private func reportResults(_ results: [TaskRunResult]) async {
        let passed = results.filter {
            if case .passed = $0.taskResult.status { return true }
            return false
        }.count

        let failed = results.filter {
            if case .failed = $0.taskResult.status { return true }
            return false
        }.count

        let warnings = results.filter {
            if case .warning = $0.taskResult.status { return true }
            return false
        }.count

        await output.summary(passed: passed, failed: failed, warnings: warnings)

        // Print diagnostics for failed tasks
        for result in results {
            if case .failed = result.taskResult.status {
                for diagnostic in result.taskResult.diagnostics {
                    await output.diagnostic(diagnostic)
                }
            }
        }
    }
}

// MARK: - HookRunResult

/// Result of running all hooks
public struct HookRunResult: Sendable {
    public let success: Bool
    public let results: [TaskRunResult]
}

// MARK: - TaskRunResult

/// Result of running a single task
public struct TaskRunResult: Sendable {
    public let taskID: String
    public let taskResult: TaskResult
    public let fixResult: FixResult?
    public let isBlocking: Bool
}

// MARK: - HookOutput

/// Protocol for hook output formatting
public protocol HookOutput: Sendable {
    func header(_ message: String) async
    func info(_ message: String) async
    func warning(_ message: String) async
    func taskStart(_ name: String) async
    func taskComplete(_ name: String, status: TaskStatus, duration: Duration?, message: String?) async
    func summary(passed: Int, failed: Int, warnings: Int) async
    func diagnostic(_ diagnostic: HookDiagnostic) async
}

extension HookOutput {
    public func taskComplete(_ name: String, status: TaskStatus, message: String?) async {
        await taskComplete(name, status: status, duration: nil, message: message)
    }
}

// MARK: - ConsoleHookOutput

/// Console output implementation with colors
public struct ConsoleHookOutput: HookOutput {
    public init() {}

    public func header(_ message: String) async {
        print("\n\u{001B}[1;33m\(message)\u{001B}[0m")
    }

    public func info(_ message: String) async {
        print("\u{001B}[0;34m\(message)\u{001B}[0m")
    }

    public func warning(_ message: String) async {
        print("\u{001B}[0;33m⚠ \(message)\u{001B}[0m")
    }

    public func taskStart(_ name: String) async {
        print("\u{001B}[0;36m▶ Running \(name)...\u{001B}[0m")
        fflush(stdout)
    }

    public func taskComplete(_ name: String, status: TaskStatus, duration: Duration?, message: String?) async {
        let icon: String
        let color: String

        switch status {
        case .passed:
            icon = "✓"
            color = "\u{001B}[0;32m"
        case .failed:
            icon = "✗"
            color = "\u{001B}[0;31m"
        case .warning:
            icon = "⚠"
            color = "\u{001B}[0;33m"
        case .skipped(let reason):
            print("\u{001B}[0;90m⊘ \(name): \(reason)\u{001B}[0m")
            return
        }

        var line = "\(color)\(icon) \(name)\u{001B}[0m"

        if let duration {
            let seconds =
                Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
            line += " \u{001B}[0;90m(\(String(format: "%.1fs", seconds)))\u{001B}[0m"
        }

        if let message {
            line += " \u{001B}[0;90m\(message)\u{001B}[0m"
        }

        print(line)
    }

    public func summary(passed: Int, failed: Int, warnings: Int) async {
        print("")
        if failed > 0 {
            print("\u{001B}[0;31m\(failed) task(s) failed\u{001B}[0m")
        } else if warnings > 0 {
            print("\u{001B}[0;33mAll tasks passed with \(warnings) warning(s)\u{001B}[0m")
        } else {
            print("\u{001B}[0;32mAll \(passed) task(s) passed!\u{001B}[0m")
        }
    }

    public func diagnostic(_ diagnostic: HookDiagnostic) async {
        print(diagnostic.xcodeFormat)
    }
}
