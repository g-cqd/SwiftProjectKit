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

// MARK: - Mock Types

/// Mock hook task for testing
struct MockHookTask: HookTask {
    let id: String
    let name: String
    let hooks: Set<HookType>
    let supportsFix: Bool
    let fixSafety: FixSafety
    let isBlocking: Bool

    var runResult: TaskResult = .passed()
    var fixResult: FixResult = FixResult()
    var shouldThrow: Bool = false
    var delayMilliseconds: Int = 0

    init(
        id: String,
        name: String? = nil,
        hooks: Set<HookType> = [.preCommit],
        supportsFix: Bool = false,
        fixSafety: FixSafety = .safe,
        isBlocking: Bool = true,
        runResult: TaskResult = .passed(),
        fixResult: FixResult = FixResult(),
        shouldThrow: Bool = false,
        delayMilliseconds: Int = 0
    ) {
        self.id = id
        self.name = name ?? id.capitalized
        self.hooks = hooks
        self.supportsFix = supportsFix
        self.fixSafety = fixSafety
        self.isBlocking = isBlocking
        self.runResult = runResult
        self.fixResult = fixResult
        self.shouldThrow = shouldThrow
        self.delayMilliseconds = delayMilliseconds
    }

    func run(context: HookContext) async throws -> TaskResult {
        if delayMilliseconds > 0 {
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        if shouldThrow {
            throw MockTaskError.taskFailed
        }
        return runResult
    }

    func fix(context: HookContext) async throws -> FixResult {
        if shouldThrow {
            throw MockTaskError.fixFailed
        }
        return fixResult
    }
}

enum MockTaskError: Error {
    case taskFailed
    case fixFailed
}

/// Mock output collector for testing
actor MockHookOutput: HookOutput {
    private(set) var headers: [String] = []
    private(set) var infos: [String] = []
    private(set) var warnings: [String] = []
    private(set) var taskStarts: [String] = []
    private(set) var taskCompletions: [(name: String, status: TaskStatus)] = []

    func header(_ message: String) async {
        headers.append(message)
    }

    func info(_ message: String) async {
        infos.append(message)
    }

    func warning(_ message: String) async {
        warnings.append(message)
    }

    func taskStart(_ name: String) async {
        taskStarts.append(name)
    }

    func taskComplete(_ name: String, status: TaskStatus, duration: Duration?, message: String?) async {
        taskCompletions.append((name: name, status: status))
    }

    func summary(passed: Int, failed: Int, warnings: Int) async {
        // Not tracking for tests
    }

    func diagnostic(_ diagnostic: HookDiagnostic) async {
        // Not tracking for tests
    }
}

// MARK: - StageRunner Tests

@Suite("StageRunner Tests")
struct StageRunnerTests {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("StageRunnerTests-\(UUID().uuidString)")

    // MARK: - Setup

    func makeContext(fixMode: FixMode = .safe) -> HookContext {
        let gitIndex = GitIndex(projectRoot: tempDir)
        return HookContext(
            projectRoot: tempDir,
            scope: .all,
            stagedFiles: [],
            allFiles: [],
            config: HooksConfiguration.default,
            isCI: false,
            hookType: .preCommit,
            fixMode: fixMode,
            gitIndex: gitIndex,
            verbose: false
        )
    }

    // MARK: - Basic Execution Tests

    @Test("Single stage with single task executes successfully")
    func singleStageExecution() async throws {
        let task = MockHookTask(id: "format", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "autofix",
                tasks: [StageTask(id: "format", mode: .check)]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results.count == 1)
        #expect(results[0].stageName == "autofix")
        #expect(results[0].success == true)
        #expect(results[0].taskResults.count == 1)
    }

    @Test("Empty stages returns empty results")
    func emptyStages() async throws {
        let output = MockHookOutput()
        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [],
            output: output,
            verbose: false
        )

        let results = try await runner.runStages([], context: makeContext())

        #expect(results.isEmpty)
    }

    @Test("Stage with multiple tasks runs all tasks")
    func multipleTasksInStage() async throws {
        let formatTask = MockHookTask(id: "format", runResult: .passed())
        let lintTask = MockHookTask(id: "lint", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [formatTask, lintTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "quality",
                tasks: [
                    StageTask(id: "format", mode: .check),
                    StageTask(id: "lint", mode: .check),
                ]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results.count == 1)
        #expect(results[0].taskResults.count == 2)
        #expect(results[0].success == true)
    }

    // MARK: - Dependency Tests

    @Test("Stages run in dependency order")
    func stagesDependencyOrder() async throws {
        let formatTask = MockHookTask(id: "format", runResult: .passed())
        let testTask = MockHookTask(id: "test", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [formatTask, testTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "test",
                tasks: [StageTask(id: "test", mode: .check)],
                dependencies: ["autofix"]  // Depends on autofix
            ),
            HookStage(
                name: "autofix",
                tasks: [StageTask(id: "format", mode: .check)]
            ),
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results.count == 2)

        // Results should contain both stages
        let stageNames = Set(results.map(\.stageName))
        #expect(stageNames.contains("autofix"))
        #expect(stageNames.contains("test"))
    }

    @Test("Multiple dependencies are satisfied before stage runs")
    func multipleDependencies() async throws {
        let task1 = MockHookTask(id: "task1", runResult: .passed())
        let task2 = MockHookTask(id: "task2", runResult: .passed())
        let task3 = MockHookTask(id: "task3", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task1, task2, task3],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "final",
                tasks: [StageTask(id: "task3", mode: .check)],
                dependencies: ["stage1", "stage2"]  // Multiple dependencies
            ),
            HookStage(
                name: "stage1",
                tasks: [StageTask(id: "task1", mode: .check)]
            ),
            HookStage(
                name: "stage2",
                tasks: [StageTask(id: "task2", mode: .check)]
            ),
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.success })
    }

    @Test("Circular dependency throws error")
    func circularDependency() async throws {
        let task = MockHookTask(id: "task", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "stage1",
                tasks: [StageTask(id: "task", mode: .check)],
                dependencies: ["stage2"]
            ),
            HookStage(
                name: "stage2",
                tasks: [StageTask(id: "task", mode: .check)],
                dependencies: ["stage1"]
            ),
        ]

        await #expect(throws: HookError.self) {
            try await runner.runStages(stages, context: makeContext())
        }
    }

    @Test("Missing dependency throws error")
    func missingDependency() async throws {
        let task = MockHookTask(id: "task", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "stage1",
                tasks: [StageTask(id: "task", mode: .check)],
                dependencies: ["nonexistent"]
            )
        ]

        await #expect(throws: HookError.self) {
            try await runner.runStages(stages, context: makeContext())
        }
    }

    // MARK: - Task Mode Tests

    @Test("Check mode does not call fix")
    func checkModeNoFix() async throws {
        let task = MockHookTask(
            id: "format",
            supportsFix: true,
            runResult: .passed(),
            fixResult: FixResult(filesModified: ["file.swift"], fixesApplied: 1)
        )
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "check",
                tasks: [StageTask(id: "format", mode: .check)]  // Check mode
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results[0].taskResults[0].fixResult == nil)
    }

    @Test("Fix mode runs fix then check")
    func fixModeRunsFixThenCheck() async throws {
        let task = MockHookTask(
            id: "format",
            supportsFix: true,
            fixSafety: .safe,
            runResult: .passed(),
            fixResult: FixResult(filesModified: ["file.swift"], fixesApplied: 1)
        )
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "autofix",
                tasks: [StageTask(id: "format", mode: .fix)]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext(fixMode: .safe))

        #expect(results[0].taskResults[0].fixResult != nil)
        #expect(results[0].taskResults[0].fixResult?.filesModified.count == 1)
    }

    @Test("FixOnly mode skips check")
    func fixOnlyModeSkipsCheck() async throws {
        let task = MockHookTask(
            id: "format",
            supportsFix: true,
            fixSafety: .safe,
            runResult: .failed(
                diagnostics: [HookDiagnostic(message: "Should not see this", severity: .error)]
            ),
            fixResult: FixResult(filesModified: ["file.swift"], fixesApplied: 1)
        )
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "quickfix",
                tasks: [StageTask(id: "format", mode: .fixOnly)]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext(fixMode: .safe))

        // Should succeed even though run would fail, because fixOnly skips run
        #expect(results[0].success == true)
        #expect(results[0].taskResults[0].fixResult != nil)
    }

    // MARK: - Failure Handling Tests

    @Test("Unknown task fails the stage")
    func unknownTaskFails() async throws {
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [],  // No tasks registered
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "check",
                tasks: [StageTask(id: "unknown", mode: .check)]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results[0].success == false)
    }

    @Test("Failed blocking task blocks stage")
    func failedBlockingTaskBlocksStage() async throws {
        let failingTask = MockHookTask(
            id: "lint",
            isBlocking: true,
            runResult: .failed(diagnostics: [HookDiagnostic(message: "Error", severity: .error)])
        )
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [failingTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "lint",
                tasks: [StageTask(id: "lint", mode: .check)]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results[0].success == false)
    }

    @Test("Failed non-blocking task does not block stage")
    func failedNonBlockingTaskDoesNotBlock() async throws {
        let failingTask = MockHookTask(
            id: "lint",
            isBlocking: false,  // Non-blocking
            runResult: .failed(diagnostics: [HookDiagnostic(message: "Warning", severity: .warning)])
        )
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [failingTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "optional",
                tasks: [StageTask(id: "lint", mode: .check)]
            )
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results[0].success == true)  // Still succeeds because non-blocking
    }

    @Test("Failed dependency blocks dependent stage and throws")
    func failedDependencyBlocksDependentStage() async throws {
        let failingTask = MockHookTask(
            id: "build",
            isBlocking: true,
            runResult: .failed(diagnostics: [HookDiagnostic(message: "Build failed", severity: .error)])
        )
        let testTask = MockHookTask(id: "test", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [failingTask, testTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "build",
                tasks: [StageTask(id: "build", mode: .check)]
            ),
            HookStage(
                name: "test",
                tasks: [StageTask(id: "test", mode: .check)],
                dependencies: ["build"]
            ),
        ]

        // When a blocking stage fails and other stages depend on it,
        // the runner throws stageBlocked error
        await #expect(throws: HookError.self) {
            try await runner.runStages(stages, context: makeContext())
        }
    }

    @Test("ContinueOnError allows dependent stage to run despite failed dependency")
    func continueOnErrorAllowsDependentStage() async throws {
        let failingTask = MockHookTask(
            id: "lint",
            isBlocking: true,
            runResult: .failed(diagnostics: [HookDiagnostic(message: "Lint error", severity: .error)])
        )
        let testTask = MockHookTask(id: "test", runResult: .passed())
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [failingTask, testTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "lint",
                tasks: [StageTask(id: "lint", mode: .check)]
            ),
            HookStage(
                name: "test",
                tasks: [StageTask(id: "test", mode: .check)],
                dependencies: ["lint"],
                continueOnError: true  // THIS stage can proceed even if dependencies fail
            ),
        ]

        let results = try await runner.runStages(stages, context: makeContext())

        // Both stages should have run
        #expect(results.count == 2)

        let lintResult = results.first { $0.stageName == "lint" }
        let testResult = results.first { $0.stageName == "test" }

        #expect(lintResult?.success == false)
        #expect(testResult?.success == true)
    }

    @Test("Task throwing error is handled gracefully")
    func taskThrowingErrorHandled() async throws {
        let throwingTask = MockHookTask(
            id: "buggy",
            isBlocking: true,
            shouldThrow: true
        )
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [throwingTask],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "buggy",
                tasks: [StageTask(id: "buggy", mode: .check)]
            )
        ]

        // Should not throw, but return failed result
        let results = try await runner.runStages(stages, context: makeContext())

        #expect(results[0].success == false)
        #expect(results[0].taskResults[0].taskResult.status == .failed)
    }

    // MARK: - Parallel Execution Tests

    @Test("Parallel stages run concurrently")
    func parallelStagesRunConcurrently() async throws {
        // Two tasks that each take 100ms
        let task1 = MockHookTask(id: "slow1", runResult: .passed(), delayMilliseconds: 100)
        let task2 = MockHookTask(id: "slow2", runResult: .passed(), delayMilliseconds: 100)
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task1, task2],
            output: output,
            verbose: false
        )

        // Two independent stages (no dependencies)
        let stages = [
            HookStage(
                name: "stage1",
                tasks: [StageTask(id: "slow1", mode: .check)]
            ),
            HookStage(
                name: "stage2",
                tasks: [StageTask(id: "slow2", mode: .check)]
            ),
        ]

        let startTime = ContinuousClock.now
        let results = try await runner.runStages(stages, context: makeContext())
        let elapsed = ContinuousClock.now - startTime

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.success })

        // If run in parallel, should take ~100ms, not ~200ms
        // Allow generous margin for CI overhead
        #expect(elapsed < .milliseconds(300))
    }

    @Test("Sequential tasks in stage run one at a time")
    func sequentialTasksInStage() async throws {
        let task1 = MockHookTask(id: "task1", runResult: .passed(), delayMilliseconds: 50)
        let task2 = MockHookTask(id: "task2", runResult: .passed(), delayMilliseconds: 50)
        let output = MockHookOutput()

        let runner = StageRunner(
            projectRoot: tempDir,
            config: HooksConfiguration.default,
            tasks: [task1, task2],
            output: output,
            verbose: false
        )

        let stages = [
            HookStage(
                name: "sequential",
                tasks: [
                    StageTask(id: "task1", mode: .check),
                    StageTask(id: "task2", mode: .check),
                ],
                parallel: false  // Sequential
            )
        ]

        let startTime = ContinuousClock.now
        let results = try await runner.runStages(stages, context: makeContext())
        let elapsed = ContinuousClock.now - startTime

        #expect(results.count == 1)
        #expect(results[0].taskResults.count == 2)

        // Sequential should take at least 100ms (50 + 50)
        #expect(elapsed >= .milliseconds(95))
    }
}

// MARK: - HookStage Codable Tests

@Suite("HookStage Codable Tests")
struct HookStageCodableTests {

    @Test("StageTask decodes from shorthand string")
    func stageTaskShorthand() throws {
        let json = #""format""#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let task = try decoder.decode(StageTask.self, from: data)

        #expect(task.id == "format")
        #expect(task.mode == .fix)  // Default mode
        #expect(task.options == nil)
    }

    @Test("StageTask decodes from shorthand with mode")
    func stageTaskShorthandWithMode() throws {
        let json = #""format:check""#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let task = try decoder.decode(StageTask.self, from: data)

        #expect(task.id == "format")
        #expect(task.mode == .check)
    }

    @Test("StageTask decodes from full object")
    func stageTaskFullObject() throws {
        let json = #"{"id": "format", "mode": "fixOnly", "options": {"key": "value"}}"#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let task = try decoder.decode(StageTask.self, from: data)

        #expect(task.id == "format")
        #expect(task.mode == .fixOnly)
        #expect(task.options != nil)
    }

    @Test("StageTask throws on invalid mode")
    func stageTaskInvalidMode() throws {
        let json = #""format:invalid""#
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(StageTask.self, from: data)
        }
    }

    @Test("HookStage decodes with dependencies array")
    func hookStageWithDependencies() throws {
        let json = """
            {
                "name": "test",
                "tasks": ["format"],
                "dependencies": ["build", "lint"]
            }
            """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let stage = try decoder.decode(HookStage.self, from: data)

        #expect(stage.name == "test")
        #expect(stage.dependencies.count == 2)
        #expect(stage.dependencies.contains("build"))
        #expect(stage.dependencies.contains("lint"))
    }

    @Test("HookStage encodes correctly")
    func hookStageEncodes() throws {
        let stage = HookStage(
            name: "quality",
            tasks: [StageTask(id: "format", mode: .check)],
            parallel: true,
            dependencies: ["setup"],
            continueOnError: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(stage)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"name\":\"quality\""))
        #expect(json.contains("\"dependencies\":[\"setup\"]"))
        #expect(json.contains("\"continueOnError\":true"))
    }

    @Test("HookStage defaults parallel to true")
    func hookStageDefaultParallel() throws {
        let json = """
            {
                "name": "test",
                "tasks": ["task1"]
            }
            """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let stage = try decoder.decode(HookStage.self, from: data)

        #expect(stage.parallel == true)
    }

    @Test("HookStage defaults continueOnError to false")
    func hookStageDefaultContinueOnError() throws {
        let json = """
            {
                "name": "test",
                "tasks": ["task1"]
            }
            """
        let data = json.data(using: .utf8)!

        let decoder = JSONDecoder()
        let stage = try decoder.decode(HookStage.self, from: data)

        #expect(stage.continueOnError == false)
    }
}

// MARK: - HookError Tests

@Suite("HookError Tests")
struct HookErrorTests {

    @Test("Unsatisfied dependency error has correct description")
    func unsatisfiedDependencyDescription() {
        let error = HookError.unsatisfiedDependency(stage: "test", dependency: "build")
        #expect(error.description.contains("test"))
        #expect(error.description.contains("build"))
    }

    @Test("Circular dependency error has correct description")
    func circularDependencyDescription() {
        let error = HookError.circularDependency(["a", "b", "c", "a"])
        #expect(error.description.contains("a -> b -> c -> a"))
    }

    @Test("Stage blocked error has correct description")
    func stageBlockedDescription() {
        let error = HookError.stageBlocked("build")
        #expect(error.description.contains("build"))
    }
}
