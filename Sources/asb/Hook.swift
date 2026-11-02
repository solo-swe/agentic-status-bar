import ArgumentParser
import ASBCore
import Foundation

/// The Claude Code hook: turns hook events into one state file per session. It must never get in
/// Claude Code's way: it prints nothing and always exits 0.
struct HookCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hook",
        abstract: "Record a Claude Code hook event (payload on stdin) in the session's state file."
    )

    func run(input: FileHandle, environment: [String: String]) {
        let started = Hook.epochMilliseconds()
        let payload = input.readDataToEndOfFile()
        Hook.handle(payload, started: started, environment: environment, parentPid: getppid(),
                    inspector: ProcessInspectors.fromEnvironment(environment))
    }
}
