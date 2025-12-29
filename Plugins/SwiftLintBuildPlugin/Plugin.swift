import Foundation
import PackagePlugin

// MARK: - SwiftLintBuildPlugin

/// Build tool plugin that runs SwiftLint on every build.
///
/// This plugin downloads SwiftLint from GitHub releases and caches it
/// in the plugin work directory. It runs as a pre-build command.
@main
struct SwiftLintBuildPlugin: BuildToolPlugin {
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

        // Ensure SwiftLint binary is available
        let swiftlintPath: URL
        do {
            swiftlintPath = try await ensureSwiftLint(
                in: context.pluginWorkDirectoryURL,
                version: defaultVersion,
            )
        } catch {
            Diagnostics.warning("SwiftLint not available: \(error.localizedDescription)")
            return []
        }

        // Build arguments
        var arguments = ["lint", "--quiet", "--reporter", "xcode"]

        // Look for config file
        if let configPath = findConfigFile(in: context.package.directoryURL) {
            arguments += ["--config", configPath.path]
        }

        // Add source files
        arguments += sourceFiles.map(\.path)

        // Create output directory
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swiftlint-output")

        return [
            .prebuildCommand(
                displayName: "SwiftLint \(target.name)",
                executable: swiftlintPath,
                arguments: arguments,
                outputFilesDirectory: outputDir,
            ),
        ]
    }

    // MARK: Private

    /// Default SwiftLint version to use
    private let defaultVersion = "0.57.1"

    // MARK: - Private Helpers

    private func findConfigFile(in directory: URL) -> URL? {
        let configNames = [".swiftlint.yml", ".swiftlint.yaml", "swiftlint.yml"]
        for name in configNames {
            let path = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    private func ensureSwiftLint(in workDirectory: URL, version: String) async throws -> URL {
        let binaryDir = workDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("swiftlint")
            .appendingPathComponent(version)
        let binaryPath = binaryDir.appendingPathComponent("swiftlint")

        // Return cached binary if exists
        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        // Download from GitHub releases
        guard let downloadURL = URL(
            string: "https://github.com/realm/SwiftLint/releases/download/\(version)/portable_swiftlint.zip",
        ) else {
            throw PluginError.downloadFailed(tool: "SwiftLint", statusCode: 0)
        }

        Diagnostics.remark("Downloading SwiftLint \(version)...")

        let (localURL, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw PluginError.downloadFailed(
                tool: "SwiftLint",
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
            throw PluginError.extractionFailed(tool: "SwiftLint")
        }

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryPath.path,
        )

        Diagnostics.remark("SwiftLint \(version) ready")
        return binaryPath
    }
}

// MARK: - Xcode Project Support

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SwiftLintBuildPlugin: XcodeBuildToolPlugin {
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

            // Check for cached binary (can't use async in Xcode plugin context)
            let binaryDir = context.pluginWorkDirectoryURL
                .appendingPathComponent("bin")
                .appendingPathComponent("swiftlint")
                .appendingPathComponent("0.57.1")
            let binaryPath = binaryDir.appendingPathComponent("swiftlint")

            // If binary doesn't exist, try to download synchronously
            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                do {
                    try downloadSwiftLintSync(to: binaryDir, version: "0.57.1")
                } catch {
                    Diagnostics.warning("SwiftLint not available: \(error.localizedDescription)")
                    return []
                }
            }

            // Build arguments
            var arguments = ["lint", "--quiet", "--reporter", "xcode"]

            // Look for config file in project directory
            if let configPath = findConfigFile(in: context.xcodeProject.directoryURL) {
                arguments += ["--config", configPath.path]
            }

            arguments += sourceFiles.map(\.path)

            let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swiftlint-output")

            return [
                .prebuildCommand(
                    displayName: "SwiftLint \(target.displayName)",
                    executable: binaryPath,
                    arguments: arguments,
                    outputFilesDirectory: outputDir,
                ),
            ]
        }

        private func findConfigFile(in directory: URL) -> URL? {
            let configNames = [".swiftlint.yml", ".swiftlint.yaml", "swiftlint.yml"]
            for name in configNames {
                let path = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: path.path) {
                    return path
                }
            }
            return nil
        }

        private func downloadSwiftLintSync(to binaryDir: URL, version: String) throws {
            guard let downloadURL = URL(
                string: "https://github.com/realm/SwiftLint/releases/download/\(version)/portable_swiftlint.zip",
            ) else {
                throw PluginError.downloadFailed(tool: "SwiftLint", statusCode: 0)
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
                throw PluginError.downloadFailed(tool: "SwiftLint", statusCode: 0)
            }

            defer { try? FileManager.default.removeItem(at: localURL) }

            // Create directory and extract
            try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", "-q", localURL.path, "-d", binaryDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            let binaryPath = binaryDir.appendingPathComponent("swiftlint")
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
