import Foundation
import PackagePlugin

// MARK: - SwiftFormatBuildPlugin

/// Build tool plugin that runs SwiftFormat on every build.
///
/// This plugin downloads SwiftFormat from GitHub releases and caches it
/// in the plugin work directory. It runs as a pre-build command.
@main
struct SwiftFormatBuildPlugin: BuildToolPlugin {
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

        // Ensure SwiftFormat binary is available
        let swiftformatPath: URL
        do {
            swiftformatPath = try await ensureSwiftFormat(
                in: context.pluginWorkDirectoryURL,
                version: defaultVersion,
            )
        } catch {
            Diagnostics.warning("SwiftFormat not available: \(error.localizedDescription)")
            return []
        }

        // Build arguments - lint mode for build (don't modify files)
        var arguments = ["--lint", "--quiet"]

        // Look for config file
        if let configPath = findConfigFile(in: context.package.directoryURL) {
            arguments += ["--config", configPath.path]
        }

        // Add source directory (more efficient than individual files)
        arguments.append(sourceTarget.directoryURL.path)

        // Create output directory
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swiftformat-output")

        return [
            .prebuildCommand(
                displayName: "SwiftFormat \(target.name)",
                executable: swiftformatPath,
                arguments: arguments,
                outputFilesDirectory: outputDir,
            ),
        ]
    }

    // MARK: Private

    /// Default SwiftFormat version to use
    private let defaultVersion = "0.54.6"

    // MARK: - Private Helpers

    private func findConfigFile(in directory: URL) -> URL? {
        let configNames = [".swiftformat"]
        for name in configNames {
            let path = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    private func ensureSwiftFormat(in workDirectory: URL, version: String) async throws -> URL {
        let binaryDir = workDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("swiftformat")
            .appendingPathComponent(version)
        let binaryPath = binaryDir.appendingPathComponent("swiftformat")

        // Return cached binary if exists
        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        // Download from GitHub releases
        let downloadURL = URL(
            string: "https://github.com/nicklockwood/SwiftFormat/releases/download/\(version)/swiftformat.zip",
        )!

        Diagnostics.remark("Downloading SwiftFormat \(version)...")

        let (localURL, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw PluginError.downloadFailed(
                tool: "SwiftFormat",
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            )
        }

        // Create directory
        try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

        // Extract zip
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", "-q", localURL.path, "-d", binaryDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw PluginError.extractionFailed(tool: "SwiftFormat")
        }

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryPath.path,
        )

        Diagnostics.remark("SwiftFormat \(version) ready")
        return binaryPath
    }
}

// MARK: - Xcode Project Support

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SwiftFormatBuildPlugin: XcodeBuildToolPlugin {
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

            // Check for cached binary
            let binaryDir = context.pluginWorkDirectoryURL
                .appendingPathComponent("bin")
                .appendingPathComponent("swiftformat")
                .appendingPathComponent("0.54.6")
            let binaryPath = binaryDir.appendingPathComponent("swiftformat")

            // If binary doesn't exist, try to download synchronously
            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                do {
                    try downloadSwiftFormatSync(to: binaryDir, version: "0.54.6")
                } catch {
                    Diagnostics.warning("SwiftFormat not available: \(error.localizedDescription)")
                    return []
                }
            }

            // Build arguments - lint mode for build
            var arguments = ["--lint", "--quiet"]

            // Look for config file in project directory
            if let configPath = findConfigFile(in: context.xcodeProject.directoryURL) {
                arguments += ["--config", configPath.path]
            }

            // Add source files
            arguments += sourceFiles.map(\.path)

            let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swiftformat-output")

            return [
                .prebuildCommand(
                    displayName: "SwiftFormat \(target.displayName)",
                    executable: binaryPath,
                    arguments: arguments,
                    outputFilesDirectory: outputDir,
                ),
            ]
        }

        private func findConfigFile(in directory: URL) -> URL? {
            let path = directory.appendingPathComponent(".swiftformat")
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
            return nil
        }

        private func downloadSwiftFormatSync(to binaryDir: URL, version: String) throws {
            let downloadURL = URL(
                string: "https://github.com/nicklockwood/SwiftFormat/releases/download/\(version)/swiftformat.zip",
            )!

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
                throw PluginError.downloadFailed(tool: "SwiftFormat", statusCode: 0)
            }

            defer { try? FileManager.default.removeItem(at: localURL) }

            try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", "-q", localURL.path, "-d", binaryDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            let binaryPath = binaryDir.appendingPathComponent("swiftformat")
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: binaryPath.path,
            )
        }
    }
#endif

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
