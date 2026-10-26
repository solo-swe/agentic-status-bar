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
        let environment = ProcessInfo.processInfo.environment
        let live = LiveInputs(
            paths: Paths.from(environment: environment), environment: environment,
            inspector: DarwinProcessInspector())
        let inputs = live.gather()
        let result = Engine.snapshot(inputs)
        live.apply(result, configText: inputs.configText)
        FileHandle.standardOutput.write(try result.snapshot.encodedJSON(pretty: pretty))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
