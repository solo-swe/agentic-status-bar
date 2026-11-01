import ArgumentParser
import ASBCore
import Foundation

struct SnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Print the reconciled sessions and the menu-bar header (doc/snapshot-schema.md)."
    )

    @Flag(help: "Print JSON (the only format for now).")
    var json = false

    @Flag(help: "Indent the JSON.")
    var pretty = false

    func run() throws {
        FileHandle.standardOutput.write(try output(environment: ProcessInfo.processInfo.environment))
    }

    /// The snapshot's JSON and a newline, after its side effects (removing dead sessions' files).
    func output(environment: [String: String]) throws -> Data {
        let live = LiveInputs(
            paths: Paths.from(environment: environment), environment: environment,
            inspector: ProcessInspectors.fromEnvironment(environment))
        let inputs = live.gather()
        let result = Engine.snapshot(inputs)
        live.apply(result, configText: inputs.configText)
        return try result.snapshot.encodedJSON(pretty: pretty) + Data("\n".utf8)
    }
}
