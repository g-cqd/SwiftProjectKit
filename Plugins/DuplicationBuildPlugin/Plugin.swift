import Foundation
import PackagePlugin

// MARK: - DuplicationBuildPlugin

/// Build tool plugin that runs duplication detection on every build.
///
/// This plugin downloads SwiftStaticAnalysis (`swa`) from GitHub releases and caches it
/// in the plugin work directory. It runs as a pre-build command with `swa duplicates`.
@main
struct DuplicationBuildPlugin: BuildToolPlugin {
    // MARK: Internal

    func createBuildCommands(
        context: PluginContext,
        target: Target,
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        // Get Swift source files
        let sourceFiles = sourceTarget.sourceFiles
            .filter { $0.url.pathExtension == "swift" }
            .map(\.url)

        guard !sourceFiles.isEmpty else {
            return []
        }

        // Ensure swa binary is available
        let swaPath: URL
        do {
            swaPath = try await ensureSWA(
                in: context.pluginWorkDirectoryURL,
                version: defaultVersion,
            )
        } catch {
            Diagnostics.warning("SwiftStaticAnalysis not available: \(error.localizedDescription)")
            return []
        }

        // Build arguments for duplication detection
        var arguments = [
            "duplicates",
            sourceTarget.directoryURL.path,
            "--format", "xcode",
        ]

        // Check for config file
        if let configPath = findConfigFile(in: context.package.directoryURL) {
            arguments += ["--config", configPath.path]
        }

        // Create output directory
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("duplicates-output")

        return [
            .prebuildCommand(
                displayName: "Duplication \(target.name)",
                executable: swaPath,
                arguments: arguments,
                outputFilesDirectory: outputDir,
            ),
        ]
    }

    // MARK: Private

    private let defaultVersion = "0.1.0"

    // swiftlint:disable:next function_body_length
    private func ensureSWA(in workDirectory: URL, version: String) async throws -> URL {
        // First, check if swa is available in PATH (system-installed)
        if let systemPath = findInPath("swa") {
            Diagnostics.remark("Using system-installed swa at \(systemPath.path)")
            return systemPath
        }

        let binaryDir = workDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("swa")
            .appendingPathComponent(version)
        let binaryPath = binaryDir.appendingPathComponent("swa")

        // Return cached binary if exists
        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        // Download from GitHub releases
        guard let downloadURL = URL(
            string: "https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v\(version)/swa-\(version)-macos-universal.tar.gz",
        ) else {
            throw PluginError.downloadFailed(tool: "swa", statusCode: 0)
        }

        Diagnostics.remark("Downloading SwiftStaticAnalysis \(version)...")

        let (localURL, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw PluginError.downloadFailed(
                tool: "swa",
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            )
        }

        // Create directory
        try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

        // Extract tar.gz
        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["xzf", localURL.path, "-C", binaryDir.path]
        try tarProcess.run()
        tarProcess.waitUntilExit()

        guard tarProcess.terminationStatus == 0 else {
            throw PluginError.extractionFailed(tool: "swa")
        }

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryPath.path,
        )

        Diagnostics.remark("SwiftStaticAnalysis \(version) ready")
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

    extension DuplicationBuildPlugin: XcodeBuildToolPlugin {
        func createBuildCommands(
            context: XcodePluginContext,
            target: XcodeTarget,
        ) throws -> [Command] {
            // Get Swift source files from Xcode target
            let sourceFiles = target.inputFiles
                .filter { $0.url.pathExtension == "swift" }
                .map(\.url)

            guard !sourceFiles.isEmpty else {
                return []
            }

            // Check for system-installed swa
            if let systemPath = findInPath("swa") {
                Diagnostics.remark("Using system-installed swa at \(systemPath.path)")
                return createDuplicatesCommand(
                    binary: systemPath,
                    targetDirectory: context.xcodeProject.directoryURL,
                    outputDir: context.pluginWorkDirectoryURL.appendingPathComponent("duplicates-output"),
                    targetName: target.displayName,
                )
            }

            // Check for cached binary
            let binaryDir = context.pluginWorkDirectoryURL
                .appendingPathComponent("bin")
                .appendingPathComponent("swa")
                .appendingPathComponent(defaultVersion)
            let binaryPath = binaryDir.appendingPathComponent("swa")

            // If binary doesn't exist, try to download synchronously
            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                do {
                    try downloadSWASync(to: binaryDir, version: defaultVersion)
                } catch {
                    Diagnostics.warning("SwiftStaticAnalysis not available: \(error.localizedDescription)")
                    return []
                }
            }

            return createDuplicatesCommand(
                binary: binaryPath,
                targetDirectory: context.xcodeProject.directoryURL,
                outputDir: context.pluginWorkDirectoryURL.appendingPathComponent("duplicates-output"),
                targetName: target.displayName,
            )
        }

        private func createDuplicatesCommand(
            binary: URL,
            targetDirectory: URL,
            outputDir: URL,
            targetName: String,
        ) -> [Command] {
            var arguments = [
                "duplicates",
                targetDirectory.path,
                "--format", "xcode",
            ]

            // Check for config file
            if let configPath = findConfigFile(in: targetDirectory) {
                arguments += ["--config", configPath.path]
            }

            return [
                .prebuildCommand(
                    displayName: "Duplication \(targetName)",
                    executable: binary,
                    arguments: arguments,
                    outputFilesDirectory: outputDir,
                ),
            ]
        }

        private func downloadSWASync(to binaryDir: URL, version: String) throws {
            guard let downloadURL = URL(
                string: "https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v\(version)/swa-\(version)-macos-universal.tar.gz",
            ) else {
                throw PluginError.downloadFailed(tool: "swa", statusCode: 0)
            }

            // Synchronous download for Xcode context
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

            if let error = downloadError {
                throw error
            }

            guard let localURL = localFileURL else {
                throw PluginError.downloadFailed(tool: "swa", statusCode: 0)
            }

            defer { try? FileManager.default.removeItem(at: localURL) }

            // Create directory and extract
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

// MARK: - PluginError

enum PluginError: Error, CustomStringConvertible {
    case downloadFailed(tool: String, statusCode: Int)
    case extractionFailed(tool: String)

    // MARK: Internal

    var description: String {
        switch self {
        case let .downloadFailed(tool, statusCode):
            "Failed to download \(tool) (HTTP \(statusCode))"

        case let .extractionFailed(tool):
            "Failed to extract \(tool) archive"
        }
    }
}
