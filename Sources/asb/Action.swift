import ArgumentParser
import ASBCore
import Foundation

struct ActionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Run a menu action (focus, toggle, set, login, reveal-config, mute-hour, mute-today, unmute, unmute-all, copy-id, copy-cwd, open-folder, reveal-transcript)."
    )

    @Argument(help: "The action.")
    var name: String

    @Argument(help: "Its arguments, usually a session ID.")
    var arguments: [String] = []

    func run() throws {
        let environment = ProcessInfo.processInfo.environment
        Actions(paths: Paths.from(environment: environment), environment: environment,
                runner: ProcessRunner(environment: environment))
            .perform(name, arguments)
    }
}
