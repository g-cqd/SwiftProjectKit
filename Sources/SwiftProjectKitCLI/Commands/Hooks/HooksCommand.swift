import ArgumentParser
import Foundation
import SwiftProjectKitCore

// MARK: - HooksCommand

struct HooksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hooks",
        abstract: "Manage git hooks for your Swift project",
        subcommands: [
            SetupCommand.self,
            RunCommand.self,
            FixCommand.self,
            ListCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )
}

// MARK: - SetupCommand

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Set up git hooks for this repository"
    )

    @Option(name: .long, help: "Path to hooks directory")
    var hooksPath: String = ".githooks"

    func run() async throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let gitIndex = GitIndex(projectRoot: projectRoot)

        // Check if we're in a git repo
        guard await gitIndex.isGitRepository() else {
            print("Error: Not a git repository")
            throw ExitCode.failure
        }

        // Create .githooks directory
        let hooksDir = projectRoot.appendingPathComponent(hooksPath)
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        // Create pre-commit hook
        let preCommitPath = hooksDir.appendingPathComponent("pre-commit")
        let preCommitContent = """
            #!/bin/sh
            # SwiftProjectKit pre-commit hook

            # Use global spk if available, otherwise download latest release
            if command -v spk >/dev/null 2>&1; then
                exec spk hooks run pre-commit
            else
                SPK=".build/spk"
                if [ ! -x "$SPK" ]; then
                    echo "Downloading latest spk..."
                    mkdir -p .build
                    ARCH=$(uname -m)
                    case "$ARCH" in
                        arm64) SUFFIX="macos-arm64" ;;
                        x86_64) SUFFIX="macos-x86_64" ;;
                        *) SUFFIX="macos-universal" ;;
                    esac
                    LATEST_URL=$(curl -sI "https://github.com/g-cqd/SwiftProjectKit/releases/latest" | grep -i "^location:" | sed 's/.*tag\\///' | tr -d '\\r\\n')
                    curl -sL "https://github.com/g-cqd/SwiftProjectKit/releases/download/${LATEST_URL}/spk-${LATEST_URL#v}-${SUFFIX}.tar.gz" | tar -xzf - -C .build
                    chmod +x "$SPK"
                fi
                exec "$SPK" hooks run pre-commit
            fi
            """
        try preCommitContent.write(to: preCommitPath, atomically: true, encoding: .utf8)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: preCommitPath.path
        )

        // Create pre-push hook
        let prePushPath = hooksDir.appendingPathComponent("pre-push")
        let prePushContent = """
            #!/bin/sh
            # SwiftProjectKit pre-push hook

            # Use global spk if available, otherwise download latest release
            if command -v spk >/dev/null 2>&1; then
                exec spk hooks run pre-push
            else
                SPK=".build/spk"
                if [ ! -x "$SPK" ]; then
                    echo "Downloading latest spk..."
                    mkdir -p .build
                    ARCH=$(uname -m)
                    case "$ARCH" in
                        arm64) SUFFIX="macos-arm64" ;;
                        x86_64) SUFFIX="macos-x86_64" ;;
                        *) SUFFIX="macos-universal" ;;
                    esac
                    LATEST_URL=$(curl -sI "https://github.com/g-cqd/SwiftProjectKit/releases/latest" | grep -i "^location:" | sed 's/.*tag\\///' | tr -d '\\r\\n')
                    curl -sL "https://github.com/g-cqd/SwiftProjectKit/releases/download/${LATEST_URL}/spk-${LATEST_URL#v}-${SUFFIX}.tar.gz" | tar -xzf - -C .build
                    chmod +x "$SPK"
                fi
                exec "$SPK" hooks run pre-push
            fi
            """
        try prePushContent.write(to: prePushPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: prePushPath.path
        )

        // Configure git to use our hooks directory
        try await gitIndex.setHooksPath(to: hooksPath)

        print("✓ Git hooks set up successfully!")
        print("")
        print("Created hooks in '\(hooksPath)/':")
        print("  • pre-commit")
        print("  • pre-push")
        print("")
        print("Git configured to use '\(hooksPath)' for hooks.")
        print("")
        print("Next steps:")
        print("  1. Add '\(hooksPath)/' to your repository")
        print("  2. Configure hooks in .spk.json (optional)")
        print("")
        print("To skip hooks temporarily: git commit --no-verify")
    }
}

// MARK: - RunCommand

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run hook tasks"
    )

    @Argument(help: "Hook type to run (pre-commit, pre-push, ci)")
    var hook: String = "pre-commit"

    @Option(name: .long, help: "Fix mode: safe, cautious, all, none")
    var fix: String = "safe"

    @Option(name: .long, help: "Only run specific tasks (comma-separated)")
    var only: String?

    @Flag(name: .shortAndLong, help: "Show verbose output (stream process stdout/stderr)")
    var verbose = false

    func run() async throws {
        let hookType: HookType
        switch hook.lowercased() {
        case "pre-commit", "precommit":
            hookType = .preCommit
        case "pre-push", "prepush":
            hookType = .prePush
        case "ci":
            hookType = .ci
        default:
            print("Error: Unknown hook type '\(hook)'")
            print("Valid options: pre-commit, pre-push, ci")
            throw ExitCode.failure
        }

        let fixMode: FixMode
        switch fix.lowercased() {
        case "safe": fixMode = .safe
        case "cautious": fixMode = .cautious
        case "all": fixMode = .all
        case "none", "check": fixMode = .none
        default:
            print("Error: Unknown fix mode '\(fix)'")
            print("Valid options: safe, cautious, all, none")
            throw ExitCode.failure
        }

        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // Load configuration
        let (config, customTasks) = try loadConfigurationWithCustomTasks(from: projectRoot)

        // Create tasks: built-in (with config applied) + custom shell tasks
        var tasks: [any HookTask] = createBuiltInTasks(from: config) + customTasks

        // Filter tasks if --only specified
        if let only {
            let allowedIDs = Set(
                only.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            )
            tasks = tasks.filter { allowedIDs.contains($0.id) }
        }

        // Create runner
        let runner = HookRunner(
            projectRoot: projectRoot,
            config: config,
            tasks: tasks,
            verbose: verbose
        )

        // Run hooks
        let result = try await runner.run(hook: hookType, fixMode: fixMode)

        if !result.success {
            throw ExitCode.failure
        }
    }

    private func loadConfigurationWithCustomTasks(
        from projectRoot: URL
    ) throws -> (HooksConfiguration, [any HookTask]) {
        let configPath = projectRoot.appendingPathComponent(".spk.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return (.default, [])
        }

        let data = try Data(contentsOf: configPath)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let hooksJson = json["hooks"] as? [String: Any] else {
            return (.default, [])
        }

        // Parse fix mode
        let fixModeStr = hooksJson["fixMode"] as? String ?? "safe"
        let fixMode: FixMode =
            switch fixModeStr {
            case "cautious": .cautious
            case "all": .all
            case "none": .none
            default: .safe
            }

        // Parse stage configs
        let preCommit = parseStageConfig(hooksJson["preCommit"] as? [String: Any])
        let prePush = parseStageConfig(hooksJson["prePush"] as? [String: Any])
        let ci = parseStageConfig(hooksJson["ci"] as? [String: Any])

        // Parse task configs and collect custom shell tasks
        var taskConfigs: [String: TaskConfig] = [:]
        var customTasks: [any HookTask] = []
        let builtInTaskIDs = Set(["format", "build", "test", "versionSync", "unused", "duplicates"])

        if let tasksJson = hooksJson["tasks"] as? [String: [String: Any]] {
            for (taskId, config) in tasksJson {
                taskConfigs[taskId] = parseTaskConfig(config)

                // Check if this is a custom shell task
                if let command = config["command"] as? String {
                    let shellTask = createShellTask(
                        id: taskId,
                        config: config,
                        command: command
                    )
                    customTasks.append(shellTask)
                } else if !builtInTaskIDs.contains(taskId) {
                    // Unknown task without command - warn but continue
                    print("Warning: Unknown task '\(taskId)' - add 'command' to make it a shell task")
                }
            }
        }

        let configuration = HooksConfiguration(
            fixMode: fixMode,
            restageFixed: hooksJson["restageFixed"] as? Bool ?? true,
            failFast: hooksJson["failFast"] as? Bool ?? false,
            preCommit: preCommit ?? .defaultPreCommit,
            prePush: prePush ?? .defaultPrePush,
            ci: ci ?? .defaultCI,
            tasks: taskConfigs
        )

        return (configuration, customTasks)
    }

    private func createBuiltInTasks(from config: HooksConfiguration) -> [any HookTask] {
        var tasks: [any HookTask] = []

        // Format task
        let formatConfig = config.tasks["format"]
        let formatPaths = formatConfig?.paths ?? ["Sources/", "Tests/"]
        tasks.append(BuiltInTasks.format(paths: formatPaths))

        // Build task
        tasks.append(BuiltInTasks.build())

        // Test task
        tasks.append(BuiltInTasks.test())

        // Version sync task
        let versionSyncConfig = config.tasks["versionSync"]
        let versionSource = parseVersionSource(from: versionSyncConfig?.options)
        let syncTargets = parseSyncTargets(from: versionSyncConfig?.options)
        tasks.append(BuiltInTasks.versionSync(source: versionSource, syncTargets: syncTargets))

        // Unused task
        let unusedConfig = config.tasks["unused"]
        let unusedPaths = unusedConfig?.paths ?? ["Sources/"]
        let unusedBlocking = unusedConfig?.blocking ?? false
        tasks.append(BuiltInTasks.unused(paths: unusedPaths, isBlocking: unusedBlocking))

        // Duplicates task
        let duplicatesConfig = config.tasks["duplicates"]
        let duplicatesPaths = duplicatesConfig?.paths ?? ["Sources/"]
        let duplicatesBlocking = duplicatesConfig?.blocking ?? false
        let minTokens = (duplicatesConfig?.options?["minTokens"]?.value as? Int) ?? 100
        tasks.append(
            BuiltInTasks.duplicates(paths: duplicatesPaths, minTokens: minTokens, isBlocking: duplicatesBlocking)
        )

        return tasks
    }

    private func parseVersionSource(from options: [String: AnyCodable]?) -> VersionSource {
        guard let options,
            let sourceTypeValue = options["sourceType"]?.value as? String
        else {
            return .default
        }

        switch sourceTypeValue.lowercased() {
        case "default", "spk":
            return .spk
        case "file":
            if let sourceFile = options["sourceFile"]?.value as? String {
                return .file(sourceFile)
            }
            return .default
        default:
            return .default
        }
    }

    private func parseSyncTargets(from options: [String: AnyCodable]?) -> [VersionSyncTask.SyncTarget] {
        guard let options,
            let targetsArray = options["syncTargets"]?.value as? [[String: Any]]
        else {
            return []
        }

        return targetsArray.compactMap { dict -> VersionSyncTask.SyncTarget? in
            guard let file = dict["file"] as? String,
                let pattern = dict["pattern"] as? String
            else {
                return nil
            }
            return VersionSyncTask.SyncTarget(file: file, pattern: pattern)
        }
    }

    private func createShellTask(
        id: String,
        config: [String: Any],
        command: String
    ) -> ShellTask {
        let fixCommand = config["fixCommand"] as? String
        let isBlocking = config["blocking"] as? Bool ?? true

        // Parse hooks from config or default to preCommit
        var hooks: Set<HookType> = []
        if let hookStrings = config["hooks"] as? [String] {
            for hookStr in hookStrings {
                switch hookStr.lowercased() {
                case "pre-commit", "precommit":
                    hooks.insert(.preCommit)
                case "pre-push", "prepush":
                    hooks.insert(.prePush)
                case "ci":
                    hooks.insert(.ci)
                default:
                    break
                }
            }
        }
        if hooks.isEmpty {
            hooks = [.preCommit, .prePush, .ci]
        }

        // Use task ID as name, or get from config
        let name = config["name"] as? String ?? id.capitalized

        return ShellTask(
            id: id,
            name: name,
            command: command,
            fixCommand: fixCommand,
            hooks: hooks,
            isBlocking: isBlocking
        )
    }

    private func parseStageConfig(_ json: [String: Any]?) -> HookStageConfig? {
        guard let json else { return nil }

        let scopeStr = json["scope"] as? String ?? "staged"
        let scope: HookScope =
            switch scopeStr {
            case "changed": .changed
            case "diff": .diff
            case "all": .all
            default: .staged
            }

        return HookStageConfig(
            enabled: json["enabled"] as? Bool ?? true,
            scope: scope,
            baseBranch: json["baseBranch"] as? String,
            parallel: json["parallel"] as? Bool ?? true,
            tasks: json["tasks"] as? [String] ?? []
        )
    }

    private func parseTaskConfig(_ json: [String: Any]) -> TaskConfig {
        let safetyStr = json["fixSafety"] as? String
        let fixSafety: FixSafety? =
            switch safetyStr {
            case "safe": .safe
            case "cautious": .cautious
            case "unsafe": .unsafe
            default: nil
            }

        return TaskConfig(
            enabled: json["enabled"] as? Bool ?? true,
            blocking: json["blocking"] as? Bool ?? true,
            fixSafety: fixSafety,
            paths: json["paths"] as? [String],
            excludePaths: json["excludePaths"] as? [String],
            options: parseOptions(json["options"] as? [String: Any])
        )
    }

    private func parseOptions(_ json: [String: Any]?) -> [String: AnyCodable]? {
        guard let json else { return nil }
        var result: [String: AnyCodable] = [:]
        for (key, value) in json {
            result[key] = AnyCodable(value)
        }
        return result
    }
}

// MARK: - FixCommand

struct FixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Apply all available fixes"
    )

    @Option(name: .long, help: "Fix mode: safe, cautious, all")
    var mode: String = "safe"

    @Option(name: .long, help: "Only fix specific tasks (comma-separated)")
    var only: String?

    @Flag(name: .shortAndLong, help: "Show verbose output (stream process stdout/stderr)")
    var verbose = false

    func run() async throws {
        let fixMode: FixMode
        switch mode.lowercased() {
        case "safe": fixMode = .safe
        case "cautious": fixMode = .cautious
        case "all": fixMode = .all
        default:
            print("Error: Unknown fix mode '\(mode)'")
            throw ExitCode.failure
        }

        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let config = HooksConfiguration.default

        var tasks: [any HookTask] = BuiltInTasks.defaults.filter(\.supportsFix)

        if let only {
            let allowedIDs = Set(only.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            tasks = tasks.filter { allowedIDs.contains($0.id) }
        }

        let runner = HookRunner(
            projectRoot: projectRoot,
            config: config,
            tasks: tasks,
            verbose: verbose
        )

        let results = try await runner.fix(fixMode: fixMode)
        let totalFixed = results.reduce(0) { $0 + $1.fixesApplied }

        if totalFixed > 0 {
            print("\n✓ Applied \(totalFixed) fix(es)")
        } else {
            print("\n✓ No fixes needed")
        }
    }
}

// MARK: - ListCommand

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available hook tasks"
    )

    func run() async throws {
        let tasks = BuiltInTasks.defaults

        print("Available tasks:\n")

        for task in tasks {
            let hooks = task.hooks.map(\.rawValue).sorted().joined(separator: ", ")
            let fixable = task.supportsFix ? " (fixable)" : ""

            print("  \(task.id)")
            print("    Name: \(task.name)")
            print("    Hooks: \(hooks)")
            print("    Blocking: \(task.isBlocking)")
            print("    Fix safety: \(task.fixSafety.rawValue)\(fixable)")
            print("")
        }
    }
}
