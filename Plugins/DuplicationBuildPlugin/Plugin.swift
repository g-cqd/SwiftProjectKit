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

        // Ensure swa binary is available (fetches latest version)
        let swaPath: URL
        do {
            swaPath = try await ensureSWA(in: context.pluginWorkDirectoryURL)
        } catch {
            Diagnostics.warning("SwiftStaticAnalysis not available: \(error.localizedDescription)")
            return []
        }

        // Build arguments for duplication detection
        var arguments = [
            "duplicates",
            sourceTarget.directoryURL.path,
            "--format", "xcode",
            "--min-tokens", "100",
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
            )
        ]
    }

    // MARK: Private

    /// Minimum supported SwiftStaticAnalysis version (0.0.16+)
    private let minimumVersion = "0.0.16"

    private func ensureSWA(in workDirectory: URL) async throws -> URL {
        // First, check if swa is available in PATH (system-installed)
        if let systemPath = findInPath("swa") {
            Diagnostics.remark("Using system-installed swa at \(systemPath.path)")
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

        // Return cached binary if exists
        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        // Download from GitHub releases
        guard
            let downloadURL = URL(
                string:
                    "https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v\(version)/swa-\(version)-macos-universal.tar.gz",
            )
        else {
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

        // Parse JSON to extract tag_name
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String
        else {
            return nil
        }

        // Remove 'v' prefix if present (e.g., "v0.0.16" -> "0.0.16")
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

            // Fetch latest version (fallback to minimum if fetch fails)
            let version = fetchLatestVersionSync() ?? minimumVersion

            // Check for cached binary
            let binaryDir = context.pluginWorkDirectoryURL
                .appendingPathComponent("bin")
                .appendingPathComponent("swa")
                .appendingPathComponent(version)
            let binaryPath = binaryDir.appendingPathComponent("swa")

            // If binary doesn't exist, try to download synchronously
            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                do {
                    try downloadSWASync(to: binaryDir, version: version)
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
                "--min-tokens", "100",
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
                )
            ]
        }

        private func downloadSWASync(to binaryDir: URL, version: String) throws {
            guard
                let downloadURL = URL(
                    string:
                        "https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v\(version)/swa-\(version)-macos-universal.tar.gz",
                )
            else {
                throw PluginError.downloadFailed(tool: "swa", statusCode: 0)
            }

            // Synchronous download using Data(contentsOf:) - thread-safe for Swift 6 concurrency
            let data: Data
            do {
                data = try Data(contentsOf: downloadURL)
            } catch {
                throw PluginError.downloadFailed(tool: "swa", statusCode: 0)
            }

            // Write to temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let localURL = tempDir.appendingPathComponent("swa-\(version).tar.gz")
            try data.write(to: localURL)
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

// MARK: - PluginError

enum PluginError: Error, CustomStringConvertible {
    case downloadFailed(tool: String, statusCode: Int)
    case extractionFailed(tool: String)

    // MARK: Internal

    var description: String {
        switch self {
        case .downloadFailed(let tool, let statusCode):
            "Failed to download \(tool) (HTTP \(statusCode))"

        case .extractionFailed(let tool):
            "Failed to extract \(tool) archive"
        }
    }
}
