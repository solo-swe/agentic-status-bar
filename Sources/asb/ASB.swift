import ArgumentParser
import ASBCore

@main
struct ASB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asb",
        abstract: "Agentic Status Bar: shows which Claude Code sessions need you.",
        version: ASBVersion.current,
        subcommands: [
            SnapshotCommand.self, ActionCommand.self, HookCommand.self,
            InstallCommand.self, UninstallCommand.self,
        ]
    )
}
