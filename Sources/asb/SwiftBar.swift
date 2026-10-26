import ArgumentParser
import ASBCore
import Foundation

struct SwiftBarCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftbar",
        abstract: "Print the menu in SwiftBar's plugin format."
    )

    @Option(help: "The SwiftBar plugin file that menu items run (with the action as its first argument). Default: asb action.")
    var plugin: String?

    func run() throws {
        let environment = ProcessInfo.processInfo.environment
        let paths = Paths.from(environment: environment)
        let live = LiveInputs(paths: paths, environment: environment, inspector: ProcessInspectors.fromEnvironment(environment))
        let inputs = live.gather()
        let result = Engine.snapshot(inputs)
        live.apply(result, configText: inputs.configText)

        let target: SwiftBarRenderer.Target = plugin.map { .plugin($0) } ?? .asb(CommandLine.executablePath)
        let settings = SwiftBarRenderer.Settings(
            config: Config.parse(inputs.configText),
            startsAtLogin: FileManager.default.fileExists(atPath: paths.loginItemFile))
        FileHandle.standardOutput.write(Data(SwiftBarRenderer.render(result.snapshot, settings: settings, target: target).utf8))
    }
}

extension CommandLine {
    /// The absolute path of the running executable.
    static var executablePath: String {
        let path = arguments[0]
        if path.hasPrefix("/") { return path }
        if path.contains("/") {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path).standardized.path
        }
        // Found through PATH.
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return dirs.map { "\($0)/\(path)" }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? path
    }
}
