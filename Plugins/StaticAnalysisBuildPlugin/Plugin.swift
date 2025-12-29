import Foundation
import PackagePlugin

// MARK: - StaticAnalysisBuildPlugin

/// Build tool plugin that runs static analysis (unused code detection) on every build.
///
/// This plugin downloads SwiftStaticAnalysis (`swa`) from GitHub releases and caches it
/// in the plugin work directory. It runs as a pre-build command.
@main
struct StaticAnalysisBuildPlugin: BuildToolPlugin {
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

        // Build arguments for unused code detection
        // --format xcode: Output in Xcode-compatible format
        // --sensible-defaults: Use sensible defaults for ignoring common patterns
        let arguments = [
            "unused",
            sourceTarget.directoryURL.path,
            "--format", "xcode",
            "--sensible-defaults",
        ]

        // Create output directory
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swa-output")

        return [
            .prebuildCommand(
                displayName: "StaticAnalysis \(target.name)",
                executable: swaPath,
                arguments: arguments,
                outputFilesDirectory: outputDir,
            ),
        ]
    }

    // MARK: Private

    /// Default SwiftStaticAnalysis version to use
    private let defaultVersion = "0.0.3"

    // MARK: - Private Helpers

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

        // Extract tar.gz (different from SwiftLint's zip)
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
}

// MARK: - Xcode Project Support

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension StaticAnalysisBuildPlugin: XcodeBuildToolPlugin {
        // swiftlint:disable:next function_body_length
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

            // First, check if swa is available in PATH (system-installed)
            if let systemPath = findInPath("swa") {
                Diagnostics.remark("Using system-installed swa at \(systemPath.path)")
                return createSWACommand(
                    binary: systemPath,
                    targetDirectory: context.xcodeProject.directoryURL,
                    outputDir: context.pluginWorkDirectoryURL.appendingPathComponent("swa-output"),
                    targetName: target.displayName,
                )
            }

            // Check for cached binary (can't use async in Xcode plugin context)
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

            return createSWACommand(
                binary: binaryPath,
                targetDirectory: context.xcodeProject.directoryURL,
                outputDir: context.pluginWorkDirectoryURL.appendingPathComponent("swa-output"),
                targetName: target.displayName,
            )
        }

        private func createSWACommand(
            binary: URL,
            targetDirectory: URL,
            outputDir: URL,
            targetName: String,
        ) -> [Command] {
            let arguments = [
                "unused",
                targetDirectory.path,
                "--format", "xcode",
                "--sensible-defaults",
            ]

            return [
                .prebuildCommand(
                    displayName: "StaticAnalysis \(targetName)",
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
    // Common paths where brew/system tools are installed
    let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    // Also check PATH environment variable
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
