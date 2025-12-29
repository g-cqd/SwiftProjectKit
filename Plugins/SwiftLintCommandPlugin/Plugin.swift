import Foundation
import PackagePlugin

// MARK: - SwiftLintCommandPlugin

/// Command plugin that runs SwiftLint on-demand.
///
/// Usage: `swift package lint [--fix] [--strict] [--target <target>]`
@main
struct SwiftLintCommandPlugin: CommandPlugin {
    // MARK: Internal

    func performCommand(
        context: PluginContext,
        arguments: [String],
    ) async throws {
        // Parse arguments
        var extractor = ArgumentExtractor(arguments)
        let fix = extractor.extractFlag(named: "fix") > 0
        let strict = extractor.extractFlag(named: "strict") > 0
        let targetNames = extractor.extractOption(named: "target")

        // Ensure SwiftLint binary is available
        let swiftlintPath = try await ensureSwiftLint(
            in: context.pluginWorkDirectoryURL,
            version: defaultVersion,
        )

        // Determine targets to lint
        let targets: [Target] = if targetNames.isEmpty {
            context.package.targets.filter { $0 is SourceModuleTarget }
        } else {
            try context.package.targets(named: targetNames)
        }

        guard !targets.isEmpty else {
            Diagnostics.warning("No targets to lint")
            return
        }

        // Build arguments
        let args = buildLintArguments(
            fix: fix,
            strict: strict,
            configDirectory: context.package.directoryURL,
            targets: targets,
        )

        // Run SwiftLint
        try runSwiftLint(
            executableURL: swiftlintPath,
            arguments: args,
            currentDirectory: context.package.directoryURL,
        )
    }

    private func buildLintArguments(
        fix: Bool,
        strict: Bool,
        configDirectory: URL,
        targets: [Target],
    ) -> [String] {
        var args = fix ? ["lint", "--fix"] : ["lint"]
        if strict {
            args.append("--strict")
        }
        args.append("--reporter")
        args.append("xcode")

        if let config = findConfigFile(in: configDirectory) {
            args += ["--config", config.path]
        }

        for target in targets {
            if let sourceTarget = target as? SourceModuleTarget {
                args.append(sourceTarget.directoryURL.path)
            }
        }
        return args
    }

    private func runSwiftLint(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL,
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
            Diagnostics.error(errors)
        }

        if process.terminationStatus != 0 {
            throw CommandError.lintingFailed(exitCode: process.terminationStatus)
        }

        print("SwiftLint completed successfully")
    }

    // MARK: Private

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

        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        guard let downloadURL = URL(
            string: "https://github.com/realm/SwiftLint/releases/download/\(version)/portable_swiftlint.zip"
        ) else {
            throw CommandError.downloadFailed(tool: "SwiftLint", statusCode: 0)
        }

        print("Downloading SwiftLint \(version)...")

        let (localURL, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw CommandError.downloadFailed(
                tool: "SwiftLint",
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            )
        }

        try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", "-q", localURL.path, "-d", binaryDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw CommandError.extractionFailed(tool: "SwiftLint")
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryPath.path,
        )

        return binaryPath
    }
}

// MARK: - Xcode Project Support

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SwiftLintCommandPlugin: XcodeCommandPlugin {
        func performCommand(
            context: XcodePluginContext,
            arguments: [String],
        ) throws {
            var extractor = ArgumentExtractor(arguments)
            let fix = extractor.extractFlag(named: "fix") > 0
            let strict = extractor.extractFlag(named: "strict") > 0

            let binaryPath = try ensureSwiftLintBinary(in: context.pluginWorkDirectoryURL)
            let args = buildXcodeArguments(
                fix: fix,
                strict: strict,
                context: context,
            )

            try runSwiftLintProcess(
                executableURL: binaryPath,
                arguments: args,
                currentDirectory: context.xcodeProject.directoryURL,
            )
        }

        private func ensureSwiftLintBinary(in workDirectory: URL) throws -> URL {
            let binaryDir = workDirectory
                .appendingPathComponent("bin")
                .appendingPathComponent("swiftlint")
                .appendingPathComponent("0.57.1")
            let binaryPath = binaryDir.appendingPathComponent("swiftlint")

            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                try downloadSwiftLintSync(to: binaryDir, version: "0.57.1")
            }

            return binaryPath
        }

        private func buildXcodeArguments(
            fix: Bool,
            strict: Bool,
            context: XcodePluginContext,
        ) -> [String] {
            var args = fix ? ["lint", "--fix"] : ["lint"]
            if strict {
                args.append("--strict")
            }
            args.append("--reporter")
            args.append("xcode")

            if let config = findConfigFile(in: context.xcodeProject.directoryURL) {
                args += ["--config", config.path]
            }

            let swiftFiles = context.xcodeProject.targets
                .flatMap(\.inputFiles)
                .filter { $0.url.pathExtension == "swift" }
                .map(\.url.path)

            args += swiftFiles
            return args
        }

        private func runSwiftLintProcess(
            executableURL: URL,
            arguments: [String],
            currentDirectory: URL,
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

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8,
            ) ?? ""
            let errors = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8,
            ) ?? ""

            if !output.isEmpty { print(output) }
            if !errors.isEmpty { Diagnostics.error(errors) }

            if process.terminationStatus != 0 {
                throw CommandError.lintingFailed(exitCode: process.terminationStatus)
            }

            print("SwiftLint completed successfully")
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
                string: "https://github.com/realm/SwiftLint/releases/download/\(version)/portable_swiftlint.zip"
            ) else {
                throw CommandError.downloadFailed(tool: "SwiftLint", statusCode: 0)
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
                throw CommandError.downloadFailed(tool: "SwiftLint", statusCode: 0)
            }

            defer { try? FileManager.default.removeItem(at: localURL) }

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

// MARK: - CommandError

enum CommandError: Error, CustomStringConvertible {
    case downloadFailed(tool: String, statusCode: Int)
    case extractionFailed(tool: String)
    case lintingFailed(exitCode: Int32)

    // MARK: Internal

    var description: String {
        switch self {
        case let .downloadFailed(tool, statusCode):
            "Failed to download \(tool) (HTTP \(statusCode))"

        case let .extractionFailed(tool):
            "Failed to extract \(tool) archive"

        case let .lintingFailed(exitCode):
            "Linting failed with exit code \(exitCode)"
        }
    }
}
