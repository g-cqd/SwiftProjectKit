# SPK CI/CD and Hooks Enhancement Plan

## Executive Summary

This plan enhances SwiftProjectKit's CI/CD workflow and hook system to:
1. Optimize CI by caching SWA binary and running checks in parallel
2. Support task dependencies and execution order in hooks
3. Enable conditional execution (tests run only after checks pass)
4. Distinguish between check-only and fix modes per-task

---

## Part 1: CI Workflow Enhancement

### Current State Analysis

The current CI workflow has these issues:
- No SWA binary caching (rebuilds or downloads each run)
- Sequential job dependencies instead of parallel where possible
- No unused/duplicates detection in CI
- No test coverage reporting
- CodeQL runs in parallel with tests instead of after

### Target Architecture (Based on SwiftStaticAnalysis)

```
┌─────────────────────────────────────────────────────────────────┐
│                         Stage 1: Setup                          │
│                    [Cache/Download SWA Binary]                   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────────┐
│ Format Check  │    │ Unused Check  │    │ Duplicates Check  │
│   (parallel)  │    │   (parallel)  │    │     (parallel)    │
└───────┬───────┘    └───────┬───────┘    └─────────┬─────────┘
        │                    │                      │
        └──────────────────────┼──────────────────────┘
                               │
                               ▼
         ┌─────────────────────────────────────────┐
         │         Stage 2: Tests + Coverage        │
         │    (builds project, runs tests, lcov)    │
         └────────────────────┬────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌─────────────────┐   ┌────────────────┐
│    CodeQL     │   │ Prepare Release │   │ Documentation  │
│  (parallel)   │   │   (parallel)    │   │   (parallel)   │
└───────────────┘   └────────┬────────┘   └────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │  Create Release │
                    │  (if new tag)   │
                    └─────────────────┘
```

### CI Implementation Tasks

#### 1.1 Add SWA Caching Job
Create a reusable setup job that:
- Checks cache for SWA binary
- Downloads from GitHub releases if not cached
- Falls back to building from source
- Uploads as artifact for dependent jobs

```yaml
cache-swa:
  name: Cache SWA
  runs-on: macos-15
  outputs:
    swa_path: ${{ steps.setup.outputs.swa_path }}
  steps:
    - uses: actions/cache@v4
      id: swa-cache
      with:
        path: ~/.local/bin/swa
        key: swa-${{ runner.os }}-v1.x.x  # Pin to version

    - name: Download SWA
      if: steps.swa-cache.outputs.cache-hit != 'true'
      run: |
        # Download latest SWA release
        curl -L ... | tar xz
        mkdir -p ~/.local/bin
        mv swa ~/.local/bin/

    - id: setup
      run: echo "swa_path=$HOME/.local/bin/swa" >> $GITHUB_OUTPUT
```

#### 1.2 Parallel Quality Checks
Three jobs running in parallel, all depending on `cache-swa`:

```yaml
format-check:
  needs: cache-swa
  steps:
    - run: ${{ needs.cache-swa.outputs.swa_path }} ... || swift-format lint

unused-check:
  needs: cache-swa
  steps:
    - run: ${{ needs.cache-swa.outputs.swa_path }} unused --mode reachability

duplicates-check:
  needs: cache-swa
  steps:
    - run: ${{ needs.cache-swa.outputs.swa_path }} duplicates --min-tokens 100
```

#### 1.3 Tests with Coverage
Single job depending on all quality checks:

```yaml
test:
  needs: [format-check, unused-check, duplicates-check]
  steps:
    - run: |
        swift test --parallel \
          --enable-code-coverage \
          --Xswiftc -profile-generate

    - name: Generate Coverage Report
      run: |
        xcrun llvm-cov export ... --format=lcov > coverage.lcov
        xcrun llvm-cov report ... > coverage.txt

    - uses: codecov/codecov-action@v4
```

#### 1.4 Post-Test Parallel Jobs
CodeQL, docs, and release prep run in parallel after tests:

```yaml
codeql:
  needs: test  # Moved to after tests

documentation:
  needs: test
  if: github.ref == 'refs/heads/main'
  steps:
    - run: swift package generate-documentation ...

prepare-release:
  needs: test
  if: startsWith(github.ref, 'refs/tags/') || ...
```

---

## Part 2: Hook System Enhancement

### Current Limitations

1. **No task dependencies**: Tasks run either all-parallel or all-sequential
2. **No conditional execution**: Can't say "run tests only if format passes"
3. **No per-stage task modes**: Can't distinguish format:check vs format:fix per hook
4. **Fixed task order**: Order is determined by array position only

### Proposed Architecture

#### 2.1 New Configuration Schema

```json
{
  "hooks": {
    "preCommit": {
      "enabled": true,
      "stages": [
        {
          "name": "checks",
          "parallel": true,
          "tasks": [
            { "id": "versionSync", "mode": "fix" },
            { "id": "format", "mode": "fix" },
            { "id": "unused", "mode": "check" },
            { "id": "duplicates", "mode": "check" }
          ]
        },
        {
          "name": "validation",
          "dependsOn": "checks",
          "tasks": [
            { "id": "test" }
          ]
        }
      ]
    },
    "prePush": {
      "stages": [
        {
          "name": "verify",
          "parallel": true,
          "tasks": [
            { "id": "versionSync", "mode": "check" },
            { "id": "format", "mode": "check" }
          ]
        }
      ]
    },
    "ci": {
      "stages": [
        {
          "name": "quality",
          "parallel": true,
          "tasks": [
            { "id": "format", "mode": "check" },
            { "id": "unused", "mode": "check" },
            { "id": "duplicates", "mode": "check" }
          ]
        },
        {
          "name": "test",
          "dependsOn": "quality",
          "tasks": [
            { "id": "test", "options": { "coverage": true } }
          ]
        }
      ]
    }
  }
}
```

#### 2.2 New Types

```swift
// MARK: - HookStage

/// A group of tasks that run together with optional dependencies
public struct HookStage: Codable, Sendable, Equatable {
    /// Unique name for this stage
    public let name: String

    /// Tasks to run in this stage
    public let tasks: [StageTask]

    /// Whether tasks in this stage run in parallel
    public let parallel: Bool

    /// Name of stage that must complete before this one
    public let dependsOn: String?

    /// Whether to continue to next stage if this fails
    public let continueOnError: Bool
}

// MARK: - StageTask

/// A task reference with per-stage configuration
public struct StageTask: Codable, Sendable, Equatable {
    /// Task identifier
    public let id: String

    /// Mode for this task in this stage
    public let mode: TaskMode

    /// Stage-specific options (merged with global task config)
    public let options: [String: AnyCodable]?
}

// MARK: - TaskMode

/// Execution mode for a task
public enum TaskMode: String, Codable, Sendable {
    /// Check only, no fixes
    case check

    /// Apply fixes then check
    case fix

    /// Fix only, no check (for pre-commit quick fixes)
    case fixOnly
}
```

#### 2.3 Enhanced HookStageConfig

```swift
public struct HookStageConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var scope: HookScope
    public var baseBranch: String?

    // NEW: Staged execution
    public var stages: [HookStage]?

    // DEPRECATED: Flat task list (for backwards compatibility)
    public var tasks: [String]
    public var parallel: Bool

    /// Resolve to stages (converts legacy format if needed)
    public var resolvedStages: [HookStage] {
        if let stages { return stages }

        // Convert legacy format to single stage
        return [HookStage(
            name: "default",
            tasks: tasks.map { StageTask(id: $0, mode: .fix, options: nil) },
            parallel: parallel,
            dependsOn: nil,
            continueOnError: false
        )]
    }
}
```

#### 2.4 Stage Runner

```swift
extension HookRunner {
    /// Run stages with dependency resolution
    func runStages(
        _ stages: [HookStage],
        context: HookContext
    ) async throws -> [StageResult] {
        var results: [String: StageResult] = [:]
        var pending = stages

        while !pending.isEmpty {
            // Find stages whose dependencies are satisfied
            let ready = pending.filter { stage in
                guard let dep = stage.dependsOn else { return true }
                guard let depResult = results[dep] else { return false }
                return depResult.success || stage.continueOnError
            }

            guard !ready.isEmpty else {
                // Circular dependency or unsatisfied deps
                throw HookError.unsatisfiedDependencies(
                    pending.map(\.name)
                )
            }

            // Run ready stages in parallel
            let stageResults = await withTaskGroup(of: StageResult.self) { group in
                for stage in ready {
                    group.addTask {
                        await self.runStage(stage, context: context)
                    }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }

            // Record results and remove from pending
            for result in stageResults {
                results[result.stageName] = result
            }
            pending.removeAll { ready.contains($0) }

            // Check for blocking failures
            let blockingFailure = stageResults.first {
                !$0.success && !$0.continueOnError
            }
            if let failure = blockingFailure {
                throw HookError.stageBlocked(failure.stageName)
            }
        }

        return Array(results.values)
    }

    private func runStage(
        _ stage: HookStage,
        context: HookContext
    ) async -> StageResult {
        let tasks = stage.tasks.compactMap { stageTask -> (any HookTask, TaskMode)? in
            guard let task = resolveTask(id: stageTask.id) else { return nil }
            return (task, stageTask.mode)
        }

        let taskResults: [TaskRunResult]
        if stage.parallel {
            taskResults = await runTasksInParallel(tasks, context: context)
        } else {
            taskResults = await runTasksSequentially(tasks, context: context)
        }

        return StageResult(
            stageName: stage.name,
            results: taskResults,
            continueOnError: stage.continueOnError
        )
    }
}
```

---

## Part 3: Default Hook Configurations

### 3.1 Pre-Commit Hook (with fixes)

**Purpose**: Quick validation before commit, auto-fix safe issues

```json
{
  "preCommit": {
    "scope": "staged",
    "stages": [
      {
        "name": "autofix",
        "parallel": true,
        "tasks": [
          { "id": "versionSync", "mode": "fix" },
          { "id": "format", "mode": "fix" }
        ]
      },
      {
        "name": "analysis",
        "parallel": true,
        "dependsOn": "autofix",
        "tasks": [
          { "id": "unused", "mode": "check" },
          { "id": "duplicates", "mode": "check" }
        ]
      },
      {
        "name": "validate",
        "dependsOn": "analysis",
        "tasks": [
          { "id": "test" }
        ]
      }
    ]
  }
}
```

**Execution Flow**:
1. Stage "autofix": Fix version + format in parallel
2. Stage "analysis": Check unused + duplicates in parallel
3. Stage "validate": Run tests
4. On any failure → abort commit

### 3.2 Pre-Push Hook (check only)

**Purpose**: Final verification before push, no modifications

```json
{
  "prePush": {
    "scope": "changed",
    "baseBranch": "main",
    "stages": [
      {
        "name": "verify",
        "parallel": true,
        "tasks": [
          { "id": "versionSync", "mode": "check" },
          { "id": "format", "mode": "check" }
        ]
      }
    ]
  }
}
```

**Execution Flow**:
1. Stage "verify": Check version + format in parallel
2. On any failure → abort push

### 3.3 CI Hook

**Purpose**: Full validation in CI environment

```json
{
  "ci": {
    "scope": "all",
    "stages": [
      {
        "name": "quality",
        "parallel": true,
        "tasks": [
          { "id": "format", "mode": "check" },
          { "id": "unused", "mode": "check" },
          { "id": "duplicates", "mode": "check" }
        ]
      },
      {
        "name": "test",
        "dependsOn": "quality",
        "tasks": [
          {
            "id": "test",
            "options": {
              "coverage": true,
              "parallel": true
            }
          }
        ]
      }
    ]
  }
}
```

---

## Part 4: Implementation Phases

### Phase 1: CI Workflow Update (This Project)
- [ ] Create optimized CI workflow for SwiftProjectKit itself
- [ ] Add SWA caching step
- [ ] Add parallel quality checks (format, unused, duplicates)
- [ ] Add test coverage reporting
- [ ] Restructure job dependencies

### Phase 2: Core Types & Configuration
- [ ] Add `HookStage` type
- [ ] Add `StageTask` type
- [ ] Add `TaskMode` enum
- [ ] Update `HookStageConfig` with stages support
- [ ] Maintain backwards compatibility with legacy format

### Phase 3: Stage Runner Implementation
- [ ] Implement stage dependency resolution
- [ ] Implement parallel stage execution
- [ ] Implement per-task mode handling
- [ ] Add stage result aggregation
- [ ] Add error handling for circular dependencies

### Phase 4: Built-in Task Updates
- [ ] Update `FormatTask` to respect `TaskMode`
- [ ] Update `VersionSyncTask` to respect `TaskMode`
- [ ] Update `UnusedTask` for standalone operation
- [ ] Update `DuplicatesTask` for standalone operation
- [ ] Add `TestTask` coverage option

### Phase 5: CI Template Generation
- [ ] Update `DefaultConfigs+CI.swift` with new patterns
- [ ] Add SWA caching template function
- [ ] Add parallel quality checks template
- [ ] Add coverage reporting template
- [ ] Update `ciWorkflow()` function signature

### Phase 6: Default Configuration Updates
- [ ] Update default pre-commit configuration
- [ ] Update default pre-push configuration
- [ ] Update default CI configuration
- [ ] Add migration guide for existing users

### Phase 7: Documentation & Testing
- [ ] Add unit tests for stage runner
- [ ] Add integration tests for hook execution
- [ ] Update CLI help text
- [ ] Document new configuration schema

---

## Part 5: File Changes Summary

### New Files
```
Sources/SwiftProjectKitCore/Hooks/
├── HookStage.swift          # New stage types
├── StageRunner.swift        # Stage execution logic
└── StageResult.swift        # Stage result types

Sources/SwiftProjectKitCore/Templates/
└── DefaultConfigs+SWA.swift # SWA caching templates
```

### Modified Files
```
Sources/SwiftProjectKitCore/Hooks/
├── HooksConfiguration.swift  # Add stage support
├── HookTypes.swift           # Add TaskMode
├── HookRunner.swift          # Integrate stage runner
└── Tasks/
    ├── FormatTask.swift      # Mode support
    ├── VersionSyncTask.swift # Mode support
    └── TestTask.swift        # Coverage option

Sources/SwiftProjectKitCore/Templates/
└── DefaultConfigs+CI.swift   # New CI templates

.github/workflows/
└── ci.yml                    # Updated workflow
```

---

## Part 6: Migration Strategy

### Backwards Compatibility

The new `stages` field is optional. If not provided:
1. Legacy `tasks` array is converted to single stage
2. Legacy `parallel` flag applies to that stage
3. All behavior remains the same

### Configuration Migration

Users can migrate incrementally:

```json
// Before (still works)
{
  "preCommit": {
    "tasks": ["format", "build"],
    "parallel": true
  }
}

// After (new features)
{
  "preCommit": {
    "stages": [
      {
        "name": "checks",
        "parallel": true,
        "tasks": [
          { "id": "format", "mode": "fix" }
        ]
      },
      {
        "name": "build",
        "dependsOn": "checks",
        "tasks": [
          { "id": "build" }
        ]
      }
    ]
  }
}
```

---

## Appendix A: Reference CI Workflow (SwiftStaticAnalysis)

Key patterns to adopt:

1. **Binary Caching**
```yaml
- uses: actions/cache@v4
  with:
    path: ~/.local/bin/swa
    key: swa-${{ runner.os }}-${{ env.SWA_VERSION }}
```

2. **Parallel Quality Checks**
```yaml
format-check:
  needs: cache-swa
duplicates-check:
  needs: cache-swa
unused-check:
  needs: cache-swa
```

3. **Sequential Test After Checks**
```yaml
test:
  needs: [format-check, duplicates-check, unused-check]
```

4. **Parallel Post-Test Jobs**
```yaml
codeql:
  needs: test
documentation:
  needs: test
prepare-release:
  needs: test
```

---

## Appendix B: Task Mode Behavior Matrix

| Task | check mode | fix mode | fixOnly mode |
|------|------------|----------|--------------|
| format | lint only | format + lint | format only |
| versionSync | verify sync | sync + verify | sync only |
| unused | report | n/a (no fix) | n/a |
| duplicates | report | n/a (no fix) | n/a |
| build | build | build | build |
| test | test | test | test |

---

## Appendix C: Error Messages

```swift
enum HookError: Error {
    case unsatisfiedDependencies([String])
    case stageBlocked(String)
    case circularDependency([String])
    case unknownTask(String)
    case invalidMode(task: String, mode: TaskMode)
}
```
