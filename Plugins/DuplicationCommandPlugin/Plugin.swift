import Foundation
import PackagePlugin

// MARK: - DuplicationCommandPlugin

/// Command plugin that runs duplication detection on-demand.
///
/// Usage: `swift package duplicates [options]`
///
/// Options:
/// - `--strict`: Use lower token threshold (30 instead of 50)
/// - `--target <name>`: Analyze specific target(s)
/// - `--min-tokens <n>`: Minimum tokens for clone detection
/// - `--types <exact|near|semantic>`: Clone types to detect
@main
struct DuplicationCommandPlugin: CommandPlugin {
    // MARK: Internal

    func performCommand(
        context: PluginContext,
        arguments: [String],
    ) async throws {
        // Parse arguments
        var extractor = ArgumentExtractor(arguments)
        let strict = extractor.extractFlag(named: "strict") > 0
        let targetNames = extractor.extractOption(named: "target")
        let minTokens = extractor.extractOption(named: "min-tokens").first
        let types = extractor.extractOption(named: "types")
        let algorithm = extractor.extractOption(named: "algorithm").first
        let excludePaths = extractor.extractOption(named: "exclude-paths")

        // Ensure swa binary is available (fetches latest version)
        let swaPath = try await ensureSWA(in: context.pluginWorkDirectoryURL)

        // Determine targets to analyze
        let targets: [Target] =
            if targetNames.isEmpty {
                context.package.targets.filter { $0 is SourceModuleTarget }
            } else {
                try context.package.targets(named: targetNames)
            }

        guard !targets.isEmpty else {
            Diagnostics.warning("No targets to analyze")
            return
        }

        // Build arguments
        var args = ["duplicates"]

        // swa only accepts one path - use package directory for multi-target analysis
        if targets.count == 1, let sourceTarget = targets.first as? SourceModuleTarget {
            args.append(sourceTarget.directoryURL.path)
        } else {
            // For multiple targets, analyze the whole package
            args.append(context.package.directoryURL.path)
        }

        // Check for config file
        if let configPath = findConfigFile(in: context.package.directoryURL) {
            args += ["--config", configPath.path]
        }

        // Exclude .build directory to prevent crashes on build artifacts
        args += ["--exclude-paths", ".build"]

        // Apply CLI options (override config file)
        args += ["--format", "text"]

        // Default min-tokens for sensible clone detection
        if let tokens = minTokens {
            args += ["--min-tokens", tokens]
        } else if strict {
            args += ["--min-tokens", "30"]
        } else {
            args += ["--min-tokens", "100"]
        }

        for type in types {
            args += ["--types", type]
        }

        if let alg = algorithm {
            args += ["--algorithm", alg]
        }

        for path in excludePaths {
            args += ["--exclude-paths", path]
        }

        try runSWA(
            executableURL: swaPath,
            arguments: args,
            currentDirectory: context.package.directoryURL,
            analysisName: "Duplication Detection",
        )
    }

    // MARK: Private

    /// Minimum supported SwiftStaticAnalysis version (0.0.16+)
    private let minimumVersion = "0.0.16"

    private func runSWA(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL,
        analysisName: String,
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Read pipes concurrently to avoid deadlock when buffer fills
        let group = DispatchGroup()
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()

        group.enter()
        DispatchQueue.global().async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.wait()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errors = String(data: errorData, encoding: .utf8) ?? ""

        if !output.isEmpty {
            print(output)
        }
        if !errors.isEmpty {
            if process.terminationStatus != 0 {
                Diagnostics.error(errors)
            } else {
                print(errors)
            }
        }

        if process.terminationStatus != 0 {
            throw CommandError.analysisFailed(name: analysisName, exitCode: process.terminationStatus)
        }

        print("\(analysisName) completed successfully")
    }

    private func ensureSWA(in workDirectory: URL) async throws -> URL {
        // First, check if swa is available in PATH
        if let systemPath = findInPath("swa") {
            print("Using system-installed swa at \(systemPath.path)")
            return systemPath
        }

        // Fetch the latest version from GitHub (fallback to minimum if fetch fails)
        let version = await fetchLatestVersion() ?? minimumVersion

        let binaryDir =
            workDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("swa")
            .appendingPathComponent(version)
        let binaryPath = binaryDir.appendingPathComponent("swa")

        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        guard
            let downloadURL = URL(
                string:
                    "https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v\(version)/swa-\(version)-macos-universal.tar.gz",
            )
        else {
            throw CommandError.downloadFailed(tool: "swa", statusCode: 0)
        }

        print("Downloading SwiftStaticAnalysis \(version)...")

        let (localURL, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse,
            (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw CommandError.downloadFailed(
                tool: "swa",
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            )
        }

        try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["xzf", localURL.path, "-C", binaryDir.path]
        try tarProcess.run()
        tarProcess.waitUntilExit()

        guard tarProcess.terminationStatus == 0 else {
            throw CommandError.extractionFailed(tool: "swa")
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryPath.path,
        )

        return binaryPath
    }

    /// Fetches the latest release version from GitHub API
    private func fetchLatestVersion() async -> String? {
        guard let url = URL(string: "https://api.github.com/repos/g-cqd/SwiftStaticAnalysis/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String
        else {
            return nil
        }

        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private func findConfigFile(in directory: URL) -> URL? {
        let configNames = [".swa.json", "swa.json"]
        for name in configNames {
            let path = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }
}

// MARK: - Xcode Project Support

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension DuplicationCommandPlugin: XcodeCommandPlugin {
        func performCommand(
            context: XcodePluginContext,
            arguments: [String],
        ) throws {
            var extractor = ArgumentExtractor(arguments)
            let strict = extractor.extractFlag(named: "strict") > 0
            let minTokens = extractor.extractOption(named: "min-tokens").first
            let types = extractor.extractOption(named: "types")
            let algorithm = extractor.extractOption(named: "algorithm").first
            let excludePaths = extractor.extractOption(named: "exclude-paths")

            let binaryPath = try ensureSWABinary(in: context.pluginWorkDirectoryURL)
            let projectDir = context.xcodeProject.directoryURL

            var args = ["duplicates", projectDir.path]

            // Check for config file
            if let configPath = findConfigFile(in: projectDir) {
                args += ["--config", configPath.path]
            }

            // Exclude build directory to prevent crashes
            args += ["--exclude-paths", "DerivedData"]
            args += ["--exclude-paths", ".build"]

            args += ["--format", "text"]

            // Default min-tokens for sensible clone detection
            if let tokens = minTokens {
                args += ["--min-tokens", tokens]
            } else if strict {
                args += ["--min-tokens", "30"]
            } else {
                args += ["--min-tokens", "100"]
            }

            for type in types {
                args += ["--types", type]
            }

            if let alg = algorithm {
                args += ["--algorithm", alg]
            }

            for path in excludePaths {
                args += ["--exclude-paths", path]
            }

            let process = Process()
            process.executableURL = binaryPath
            process.arguments = args
            process.currentDirectoryURL = projectDir

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output =
                String(
                    data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8,
                ) ?? ""
            let errors =
                String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8,
                ) ?? ""

            if !output.isEmpty { print(output) }
            if !errors.isEmpty { Diagnostics.error(errors) }

            if process.terminationStatus != 0 {
                throw CommandError.analysisFailed(name: "duplicates", exitCode: process.terminationStatus)
            }

            print("Duplication detection completed successfully")
        }

        private func ensureSWABinary(in workDirectory: URL) throws -> URL {
            // Check system PATH first
            if let systemPath = findInPath("swa") {
                print("Using system-installed swa at \(systemPath.path)")
                return systemPath
            }

            // Fetch latest version (fallback to minimum if fetch fails)
            let version = fetchLatestVersionSync() ?? minimumVersion

            let binaryDir =
                workDirectory
                .appendingPathComponent("bin")
                .appendingPathComponent("swa")
                .appendingPathComponent(version)
            let binaryPath = binaryDir.appendingPathComponent("swa")

            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                try downloadSWASync(to: binaryDir, version: version)
            }

            return binaryPath
        }

        private func downloadSWASync(to binaryDir: URL, version: String) throws {
            guard
                let downloadURL = URL(
                    string:
                        "https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v\(version)/swa-\(version)-macos-universal.tar.gz",
                )
            else {
                throw CommandError.downloadFailed(tool: "swa", statusCode: 0)
            }

            // Synchronous download using Data(contentsOf:) - thread-safe for Swift 6 concurrency
            let data: Data
            do {
                data = try Data(contentsOf: downloadURL)
            } catch {
                throw CommandError.downloadFailed(tool: "swa", statusCode: 0)
            }

            // Write to temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let localURL = tempDir.appendingPathComponent("swa-\(version).tar.gz")
            try data.write(to: localURL)
            defer { try? FileManager.default.removeItem(at: localURL) }

            try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

            let tarProcess = Process()
            tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tarProcess.arguments = ["xzf", localURL.path, "-C", binaryDir.path]
            try tarProcess.run()
            tarProcess.waitUntilExit()

            let binaryPath = binaryDir.appendingPathComponent("swa")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: binaryPath.path,
            )
        }

        /// Fetches the latest release version from GitHub API (synchronous)
        private func fetchLatestVersionSync() -> String? {
            guard let url = URL(string: "https://api.github.com/repos/g-cqd/SwiftStaticAnalysis/releases/latest") else {
                return nil
            }

            // Synchronous fetch using Data(contentsOf:) - thread-safe for Swift 6 concurrency
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }

            // Parse JSON to extract tag_name
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tagName = json["tag_name"] as? String
            else {
                return nil
            }

            // Remove 'v' prefix if present (e.g., "v0.0.16" -> "0.0.16")
            return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }
#endif

// MARK: - PATH Lookup

/// Find an executable in the system PATH
private func findInPath(_ executable: String) -> URL? {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let searchPaths = [
        homeDir.appendingPathComponent(".local/bin").path,
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let allPaths = searchPaths + envPath.split(separator: ":").map(String.init)

    for dir in allPaths {
        let fullPath = URL(fileURLWithPath: dir).appendingPathComponent(executable)
        if FileManager.default.isExecutableFile(atPath: fullPath.path) {
            return fullPath
        }
    }
    return nil
}

// MARK: - CommandError

enum CommandError: Error, CustomStringConvertible {
    case downloadFailed(tool: String, statusCode: Int)
    case extractionFailed(tool: String)
    case analysisFailed(name: String, exitCode: Int32)

    // MARK: Internal

    var description: String {
        switch self {
        case .downloadFailed(let tool, let statusCode):
            "Failed to download \(tool) (HTTP \(statusCode))"

        case .extractionFailed(let tool):
            "Failed to extract \(tool) archive"

        case .analysisFailed(let name, let exitCode):
            "\(name) failed with exit code \(exitCode)"
        }
    }
}
