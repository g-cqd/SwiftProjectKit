import Foundation
import PackagePlugin

// MARK: - SwiftFormatCommandPlugin

/// Command plugin that runs swift-format on-demand.
///
/// Usage: `swift package format-source-code [--lint] [--target <target>]`
@main
struct SwiftFormatCommandPlugin: CommandPlugin {
    // MARK: Internal

    func performCommand(
        context: PluginContext,
        arguments: [String],
    ) async throws {
        // Parse arguments
        var extractor = ArgumentExtractor(arguments)
        let lint = extractor.extractFlag(named: "lint") > 0
        let recursive = extractor.extractFlag(named: "recursive") > 0
        let targetNames = extractor.extractOption(named: "target")

        // Find swift-format
        let swiftFormatPath = try findSwiftFormat()
        print("Using swift-format at \(swiftFormatPath.path)")

        // Determine targets to format
        let targets: [Target] =
            if targetNames.isEmpty {
                context.package.targets.filter { $0 is SourceModuleTarget }
            } else {
                try context.package.targets(named: targetNames)
            }

        guard !targets.isEmpty else {
            Diagnostics.warning("No targets to format")
            return
        }

        // Build arguments
        let args = buildFormatArguments(
            lint: lint,
            recursive: recursive,
            configDirectory: context.package.directoryURL,
            targets: targets,
        )

        // Run swift-format
        try runSwiftFormat(
            executableURL: swiftFormatPath,
            arguments: args,
            currentDirectory: context.package.directoryURL,
            isLintMode: lint,
        )
    }

    // MARK: Private

    private func buildFormatArguments(
        lint: Bool,
        recursive: Bool,
        configDirectory: URL,
        targets: [Target],
    ) -> [String] {
        var args: [String] = []

        // Add subcommand (lint or format)
        if lint {
            args.append("lint")
            args.append("--strict")
        } else {
            args.append("format")
            args.append("--in-place")
        }

        args.append("--parallel")

        if let config = findConfigFile(in: configDirectory) {
            args += ["--configuration", config.path]
        }

        if recursive {
            args.append("--recursive")
        }

        for target in targets {
            if let sourceTarget = target as? SourceModuleTarget {
                args.append(sourceTarget.directoryURL.path)
            }
        }
        return args
    }

    private func runSwiftFormat(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL,
        isLintMode: Bool,
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
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errors = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

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
            throw CommandError.formattingFailed(exitCode: process.terminationStatus)
        }

        let action = isLintMode ? "checked" : "formatted"
        print("swift-format \(action) successfully")
    }

    private func findConfigFile(in directory: URL) -> URL? {
        let path = directory.appendingPathComponent(".swift-format")
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return nil
    }

    private func findSwiftFormat() throws -> URL {
        // First check for swift-format in common paths
        if let systemPath = findInPath("swift-format") {
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
            throw CommandError.toolNotFound(tool: "swift-format")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            throw CommandError.toolNotFound(tool: "swift-format")
        }

        return URL(fileURLWithPath: path)
    }
}

// MARK: - Xcode Project Support

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SwiftFormatCommandPlugin: XcodeCommandPlugin {
        func performCommand(
            context: XcodePluginContext,
            arguments: [String],
        ) throws {
            var extractor = ArgumentExtractor(arguments)
            let lint = extractor.extractFlag(named: "lint") > 0

            let swiftFormatPath = try findSwiftFormat()
            print("Using swift-format at \(swiftFormatPath.path)")

            let args = buildXcodeArguments(
                lint: lint,
                context: context,
            )

            try runSwiftFormatProcess(
                executableURL: swiftFormatPath,
                arguments: args,
                currentDirectory: context.xcodeProject.directoryURL,
                isLintMode: lint,
            )
        }

        private func buildXcodeArguments(
            lint: Bool,
            context: XcodePluginContext,
        ) -> [String] {
            var args: [String] = []

            if lint {
                args.append("lint")
                args.append("--strict")
            } else {
                args.append("format")
                args.append("--in-place")
            }

            args.append("--parallel")

            if let config = findConfigFile(in: context.xcodeProject.directoryURL) {
                args += ["--configuration", config.path]
            }

            let swiftFiles = context.xcodeProject.targets
                .flatMap(\.inputFiles)
                .filter { $0.url.pathExtension == "swift" }
                .map(\.url.path)

            args += swiftFiles
            return args
        }

        private func runSwiftFormatProcess(
            executableURL: URL,
            arguments: [String],
            currentDirectory: URL,
            isLintMode: Bool,
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
            if !errors.isEmpty {
                if process.terminationStatus != 0 {
                    Diagnostics.error(errors)
                } else {
                    print(errors)
                }
            }

            if process.terminationStatus != 0 {
                throw CommandError.formattingFailed(exitCode: process.terminationStatus)
            }

            let action = isLintMode ? "checked" : "formatted"
            print("swift-format \(action) successfully")
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

// MARK: - CommandError

enum CommandError: Error, CustomStringConvertible {
    case toolNotFound(tool: String)
    case formattingFailed(exitCode: Int32)

    // MARK: Internal

    var description: String {
        switch self {
        case .toolNotFound(let tool):
            "\(tool) not found. Ensure Xcode is installed and xcode-select is configured."

        case .formattingFailed(let exitCode):
            "Formatting failed with exit code \(exitCode)"
        }
    }
}
