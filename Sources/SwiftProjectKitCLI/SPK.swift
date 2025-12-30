import ArgumentParser
import Foundation
import SwiftProjectKitCore

@main
struct SPK: AsyncParsableCommand {
    // swa:ignore-unused
    static let configuration = CommandConfiguration(
        commandName: "spk",
        abstract: "Swift Project Kit - Opinionated tooling for Swift projects by g-cqd",
        version: swiftProjectKitVersion,
        subcommands: [
            InitCommand.self,
            SyncCommand.self,
            UpdateCommand.self,
            LintCommand.self,
            FormatCommand.self,
            WorkflowCommand.self,
        ],
        defaultSubcommand: nil,
    )
}
