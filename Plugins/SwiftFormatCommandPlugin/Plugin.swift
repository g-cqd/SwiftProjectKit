import Foundation
import PackagePlugin

// MARK: - SwiftFormatCommandPlugin

/// Command plugin that runs SwiftFormat on-demand.
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
        let verbose = extractor.extractFlag(named: "verbose") > 0
        let targetNames = extractor.extractOption(named: "target")

        // Ensure SwiftFormat binary is available
        let swiftformatPath = try await ensureSwiftFormat(
            in: context.pluginWorkDirectoryURL,
            version: defaultVersion,
        )

        // Determine targets to format
        let targets: [Target] = if targetNames.isEmpty {
            context.package.targets.filter { $0 is SourceModuleTarget }
        } else {
            try context.package.targets(named: targetNames)
        }

        guard !targets.isEmpty else {
            Diagnostics.warning("No targets to format")
            return
        }

        // Build arguments
        var args: [String] = []
        if lint {
            args.append("--lint")
        }
        if verbose {
            args.append("--verbose")
        }

        // Find config
        if let config = findConfigFile(in: context.package.directoryURL) {
            args += ["--config", config.path]
        }

        // Add source directories
        for target in targets {
            if let sourceTarget = target as? SourceModuleTarget {
                args.append(sourceTarget.directoryURL.path)
            }
        }

        // Run SwiftFormat
        let process = Process()
        process.executableURL = swiftformatPath
        process.arguments = args
        process.currentDirectoryURL = context.package.directoryURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        // Output results
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errors = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if !output.isEmpty {
            print(output)
        }
        if !errors.isEmpty {
            Diagnostics.error(errors)
        }

        if process.terminationStatus != 0 {
            throw CommandError.formattingFailed(exitCode: process.terminationStatus)
        }

        let action = lint ? "checked" : "formatted"
        print("SwiftFormat \(action) successfully")
    }

    // MARK: Private

    private let defaultVersion = "0.54.6"

    // MARK: - Private Helpers

    private func findConfigFile(in directory: URL) -> URL? {
        let path = directory.appendingPathComponent(".swiftformat")
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return nil
    }

    private func ensureSwiftFormat(in workDirectory: URL, version: String) async throws -> URL {
        let binaryDir = workDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("swiftformat")
            .appendingPathComponent(version)
        let binaryPath = binaryDir.appendingPathComponent("swiftformat")

        if FileManager.default.fileExists(atPath: binaryPath.path) {
            return binaryPath
        }

        guard let downloadURL = URL(
            string: "https://github.com/nicklockwood/SwiftFormat/releases/download/\(version)/swiftformat.zip"
        ) else {
            throw CommandError.downloadFailed(tool: "SwiftFormat", statusCode: 0)
        }

        print("Downloading SwiftFormat \(version)...")

        let (localURL, response) = try await URLSession.shared.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw CommandError.downloadFailed(
                tool: "SwiftFormat",
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
            throw CommandError.extractionFailed(tool: "SwiftFormat")
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

    extension SwiftFormatCommandPlugin: XcodeCommandPlugin {
        func performCommand(
            context: XcodePluginContext,
            arguments: [String],
        ) throws {
            var extractor = ArgumentExtractor(arguments)
            let lint = extractor.extractFlag(named: "lint") > 0
            let verbose = extractor.extractFlag(named: "verbose") > 0

            // Check for binary
            let binaryDir = context.pluginWorkDirectoryURL
                .appendingPathComponent("bin")
                .appendingPathComponent("swiftformat")
                .appendingPathComponent("0.54.6")
            let binaryPath = binaryDir.appendingPathComponent("swiftformat")

            if !FileManager.default.fileExists(atPath: binaryPath.path) {
                try downloadSwiftFormatSync(to: binaryDir, version: "0.54.6")
            }

            var args: [String] = []
            if lint {
                args.append("--lint")
            }
            if verbose {
                args.append("--verbose")
            }

            if let config = findConfigFile(in: context.xcodeProject.directoryURL) {
                args += ["--config", config.path]
            }

            // Add all Swift files from all targets
            let swiftFiles = context.xcodeProject.targets
                .flatMap(\.inputFiles)
                .filter { $0.url.pathExtension == "swift" }
                .map(\.url.path)

            args += swiftFiles

            let process = Process()
            process.executableURL = binaryPath
            process.arguments = args
            process.currentDirectoryURL = context.xcodeProject.directoryURL

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errors = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if !output.isEmpty { print(output) }
            if !errors.isEmpty { Diagnostics.error(errors) }

            if process.terminationStatus != 0 {
                throw CommandError.formattingFailed(exitCode: process.terminationStatus)
            }

            let action = lint ? "checked" : "formatted"
            print("SwiftFormat \(action) successfully")
        }

        private func findConfigFile(in directory: URL) -> URL? {
            let path = directory.appendingPathComponent(".swiftformat")
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
            return nil
        }

        private func downloadSwiftFormatSync(to binaryDir: URL, version: String) throws {
            guard let downloadURL = URL(
                string: "https://github.com/nicklockwood/SwiftFormat/releases/download/\(version)/swiftformat.zip"
            ) else {
                throw CommandError.downloadFailed(tool: "SwiftFormat", statusCode: 0)
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
                throw CommandError.downloadFailed(tool: "SwiftFormat", statusCode: 0)
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

// MARK: - CommandError

enum CommandError: Error, CustomStringConvertible {
    case downloadFailed(tool: String, statusCode: Int)
    case extractionFailed(tool: String)
    case formattingFailed(exitCode: Int32)

    // MARK: Internal

    var description: String {
        switch self {
        case let .downloadFailed(tool, statusCode):
            "Failed to download \(tool) (HTTP \(statusCode))"

        case let .extractionFailed(tool):
            "Failed to extract \(tool) archive"

        case let .formattingFailed(exitCode):
            "Formatting failed with exit code \(exitCode)"
        }
    }
}
