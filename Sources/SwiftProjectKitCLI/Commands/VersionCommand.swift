import ArgumentParser
import Foundation

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Display the project version from .spk.json"
    )

    @Option(name: .shortAndLong, help: "Path to project directory")
    var path: String?

    @Flag(name: .long, help: "Output only the version number (for scripts)")
    var quiet = false

    func run() throws {
        let projectRoot =
            path.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let configPath = projectRoot.appendingPathComponent(".spk.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw ValidationError("No .spk.json found in \(projectRoot.path)")
        }

        let data = try Data(contentsOf: configPath)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let projectJson = json?["project"] as? [String: Any],
            let version = projectJson["version"] as? String
        else {
            throw ValidationError("No project.version found in .spk.json")
        }

        if quiet {
            print(version)
        } else {
            print("Project version: \(version)")
        }
    }
}
