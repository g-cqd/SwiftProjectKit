import Foundation
import PackagePlugin

// MARK: - UnusedCodeCommandPlugin

/// Command plugin that runs unused code detection on-demand.
///
/// Usage: `swift package unused [options]`
///
/// Options:
/// - `--strict`: Use low confidence threshold
/// - `--target <name>`: Analyze specific target(s)
/// - `--mode <simple|reachability>`: Detection mode
/// - `--sensible-defaults`: Apply sensible exclusion defaults
@main
struct UnusedCodeCommandPlugin: CommandPlugin {
    // MARK: Internal

    func performCommand(
        context: PluginContext,
        arguments: [String],
    ) async throws {
        // Parse arguments
        var extractor = ArgumentExtractor(arguments)
        let strict = extractor.extractFlag(named: "strict") > 0
        let targetNames = extractor.extractOption(named: "target")
        let mode = extractor.extractOption(named: "mode").first ?? "reachability"
        let minConfidence = extractor.extractOption(named: "min-confidence").first
        let sensibleDefaults = extractor.extractFlag(named: "sensible-defaults") > 0
        let ignorePublic = extractor.extractFlag(named: "ignore-public") > 0
        let excludePaths = extractor.extractOption(named: "exclude-paths")

        // Ensure swa binary is available
        let swaPath = try await ensureSWA(
            in: context.pluginWorkDirectoryURL,
            version: defaultVersion,
        )

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
        var args = ["unused"]

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

        // Apply CLI options (override config file)
        args += ["--mode", mode]
        args += ["--format", "text"]

        if sensibleDefaults {
            args.append("--sensible-defaults")
        }

        if ignorePublic {
            args.append("--ignore-public")
        }

        if let minConf = minConfidence {
            args += ["--min-confidence", minConf]
        } else if strict {
            args += ["--min-confidence", "low"]
        }

        for path in excludePaths {
            args += ["--exclude-paths", path]
        }

        try runSWA(
            executableURL: swaPath,
            arguments: args,
            currentDirectory: context.package.directoryURL,
            analysisName: "Unused Code Detection",
        )
    }

    // MARK: Private

    private let defaultVersion = "0.0.6"

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

    private func ensureSWA(in workDirectory: URL, version: String) async throws -> URL {
        // First, check if swa is available in PATH
        if let systemPath = findInPath("swa") {
            print("Using system-installed swa at \(systemPath.path)")
            return systemPath
        }

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

    extension UnusedCodeCommandPlugin: XcodeCommandPlugin {
        func performCommand(
            context: XcodePluginContext,
            arguments: [String],
        ) throws {
            var extractor = ArgumentExtractor(arguments)
            let strict = extractor.extractFlag(named: "strict") > 0
            let mode = extractor.extractOption(named: "mode").first ?? "reachability"
            let minConfidence = extractor.extractOption(named: "min-confidence").first
            let sensibleDefaults = extractor.extractFlag(named: "sensible-defaults") > 0
            let ignorePublic = extractor.extractFlag(named: "ignore-public") > 0
            let excludePaths = extractor.extractOption(named: "exclude-paths")

            let binaryPath = try ensureSWABinary(in: context.pluginWorkDirectoryURL)
            let projectDir = context.xcodeProject.directoryURL

            var args = ["unused", projectDir.path]

            // Check for config file
            if let configPath = findConfigFile(in: projectDir) {
                args += ["--config", configPath.path]
            }

            args += ["--mode", mode]
            args += ["--format", "text"]

            if sensibleDefaults {
                args.append("--sensible-defaults")
            }

            if ignorePublic {
                args.append("--ignore-public")
            }

            if let minConf = minConfidence {
                args += ["--min-confidence", minConf]
            } else if strict {
                args += ["--min-confidence", "low"]
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
                throw CommandError.analysisFailed(name: "unused", exitCode: process.terminationStatus)
            }

            print("Unused code detection completed successfully")
        }

        private func ensureSWABinary(in workDirectory: URL) throws -> URL {
            // Check system PATH first
            if let systemPath = findInPath("swa") {
                print("Using system-installed swa at \(systemPath.path)")
                return systemPath
            }

            let binaryDir =
                workDirectory
                .appendingPathComponent("bin")
                .appendingPathComponent("swa")
                .appendingPathComponent(defaultVersion)
            let binaryPath = binaryDir.appendingPathComponent("swa")

            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                try downloadSWASync(to: binaryDir, version: defaultVersion)
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

            let semaphore = DispatchSemaphore(value: 0)
            var downloadError: Error?
            var localFileURL: URL?

            let task = URLSession.shared.downloadTask(with: downloadURL) { url, _, error in
                localFileURL = url
                downloadError = error
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()

            if let error = downloadError { throw error }
            guard let localURL = localFileURL else {
                throw CommandError.downloadFailed(tool: "swa", statusCode: 0)
            }

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
    }
#endif

// MARK: - PATH Lookup

/// Find an executable in the system PATH
private func findInPath(_ executable: String) -> URL? {
    let searchPaths = [
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
