import Foundation
import PackagePlugin

// MARK: - SwiftFormatBuildPlugin

/// Build tool plugin that runs swift-format on every build.
///
/// This plugin uses the swift-format tool from the Xcode toolchain (via xcrun).
/// It runs as a pre-build command in lint mode (non-destructive).
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

        // Find swift-format via xcrun
        let swiftFormatPath: URL
        do {
            swiftFormatPath = try findSwiftFormat()
        } catch {
            Diagnostics.warning("swift-format not available: \(error.localizedDescription)")
            return []
        }

        // Build arguments - lint mode for build (don't modify files)
        var arguments = ["lint", "--strict", "--parallel"]

        // Look for config file
        if let configPath = findConfigFile(in: context.package.directoryURL) {
            arguments += ["--configuration", configPath.path]
        }

        // Add source files
        arguments += sourceFiles.map(\.path)

        // Create output directory
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swift-format-output")

        return [
            .prebuildCommand(
                displayName: "swift-format \(target.name)",
                executable: swiftFormatPath,
                arguments: arguments,
                outputFilesDirectory: outputDir,
            )
        ]
    }

    // MARK: Private

    private func findConfigFile(in directory: URL) -> URL? {
        let configNames = [".swift-format"]
        for name in configNames {
            let path = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    private func findSwiftFormat() throws -> URL {
        // First check for swift-format in common paths
        if let systemPath = findInPath("swift-format") {
            Diagnostics.remark("Using swift-format at \(systemPath.path)")
            return systemPath
        }

        // Try xcrun to find swift-format from Xcode toolchain
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let pipe = Pipe()

        let process = Process()
        process.executableURL = xcrunURL
        process.arguments = ["--find", "swift-format"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PluginError.toolNotFound(tool: "swift-format")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            throw PluginError.toolNotFound(tool: "swift-format")
        }

        let url = URL(fileURLWithPath: path)
        Diagnostics.remark("Using swift-format from Xcode toolchain at \(path)")
        return url
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

            // Find swift-format via xcrun
            let swiftFormatPath: URL
            do {
                swiftFormatPath = try findSwiftFormat()
            } catch {
                Diagnostics.warning("swift-format not available: \(error.localizedDescription)")
                return []
            }

            // Build arguments - lint mode for build
            var arguments = ["lint", "--strict", "--parallel"]

            // Look for config file in project directory
            if let configPath = findConfigFile(in: context.xcodeProject.directoryURL) {
                arguments += ["--configuration", configPath.path]
            }

            // Add source files
            arguments += sourceFiles.map(\.path)

            let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("swift-format-output")

            return [
                .prebuildCommand(
                    displayName: "swift-format \(target.displayName)",
                    executable: swiftFormatPath,
                    arguments: arguments,
                    outputFilesDirectory: outputDir,
                )
            ]
        }

        private func findConfigFile(in directory: URL) -> URL? {
            let path = directory.appendingPathComponent(".swift-format")
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
            return nil
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
    case toolNotFound(tool: String)

    // MARK: Internal

    var description: String {
        switch self {
        case .toolNotFound(let tool):
            "\(tool) not found. Ensure Xcode is installed and xcode-select is configured."
        }
    }
}
