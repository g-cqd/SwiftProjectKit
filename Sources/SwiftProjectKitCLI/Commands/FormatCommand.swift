import ArgumentParser
import Foundation

struct FormatCommand: AsyncParsableCommand {
    // swa:ignore-unused
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Run swift-format on the project",
    )

    @Option(name: .shortAndLong, help: "Path to format")
    var path: String = "."

    @Flag(name: .long, help: "Check only - don't modify files")
    var lint = false

    @Flag(name: .long, help: "Process files recursively")
    var recursive = true

    func run() async throws {
        let projectURL = URL(fileURLWithPath: path)

        // Find swift-format via xcrun
        let swiftFormatPath = try findSwiftFormat()
        print("Using swift-format at \(swiftFormatPath.path)")

        // Build arguments
        var args: [String] = []

        if lint {
            args.append("lint")
            args.append("--strict")
        } else {
            args.append("format")
            args.append("--in-place")
        }

        args.append("--parallel")

        if recursive {
            args.append("--recursive")
        }

        // Find config
        let configPath = projectURL.appendingPathComponent(".swift-format")
        if FileManager.default.fileExists(atPath: configPath.path) {
            args += ["--configuration", configPath.path]
        }

        // Add path
        args.append(projectURL.path)

        print("Running swift-format\(lint ? " (lint mode)" : "")...")

        let process = Process()
        process.executableURL = swiftFormatPath
        process.arguments = args
        process.currentDirectoryURL = projectURL

        try process.run()
        process.waitUntilExit()

        let action = lint ? "checked" : "formatted"
        guard process.terminationStatus == 0 else {
            print("swift-format found issues (exit code: \(process.terminationStatus))")
            throw ExitCode(process.terminationStatus)
        }
        print("swift-format \(action) successfully")
    }

    private func findSwiftFormat() throws -> URL {
        // First check for swift-format in common paths
        let searchPaths = [
            "/opt/homebrew/bin/swift-format",
            "/usr/local/bin/swift-format",
            "/usr/bin/swift-format",
        ]

        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: path) {
                return url
            }
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
            throw CLIError.toolNotFound("swift-format")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            throw CLIError.toolNotFound("swift-format")
        }

        return URL(fileURLWithPath: path)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case toolNotFound(String)

    // swa:ignore-unused - Required by CustomStringConvertible protocol
    var description: String {
        switch self {
        case .toolNotFound(let tool):
            "\(tool) not found. Ensure Xcode is installed and xcode-select is configured."
        }
    }
}
