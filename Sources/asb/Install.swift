import ArgumentParser
import ASBCore
import Foundation

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Add the hooks to Claude Code's settings. Safe to run again."
    )

    func run() throws {
        try run(Setup.installer())
    }

    func run(_ installer: Installer) throws {
        try Setup.reportingInvalidSettings { try installer.install() }
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove what asb install added. Asks before deleting state and config (--purge deletes them)."
    )

    @Flag(help: "Also delete the state files and the config without asking.")
    var purge = false

    func run() throws {
        let installer = Setup.installer()
        try run(installer, confirmPurge: { Self.askToPurge(installer) })
    }

    func run(_ installer: Installer, confirmPurge: () -> Bool) throws {
        try Setup.reportingInvalidSettings { try installer.uninstall(purge: purge, confirmPurge: confirmPurge) }
    }

    static func askToPurge(_ installer: Installer) -> Bool {
        guard isatty(0) == 1 else { return false }
        print("Also delete \(installer.stateDir) and \(installer.configFile)? [y/N] ", terminator: "")
        return ["y", "yes"].contains((readLine() ?? "").lowercased())
    }
}

enum Setup {
    /// An installer for this machine and the asb being run. Overrides: `ASB_SETTINGS` (settings file),
    /// `ASB_SWIFTBAR_DIR` (SwiftBar's plugin folder, where an old link of ours is removed).
    static func installer(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        argv0: String = CommandLine.arguments[0],
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> Installer {
        let executable = ExecutablePath.resolve(argv0, currentDirectory: currentDirectory, searchPath: environment["PATH"])
        let home = Paths.from(environment: environment).home
        return Installer.forMachine(
            environment: environment, sourceBinary: executable,
            swiftBarDir: Installer.swiftBarDir(environment: environment, home: home))
    }

    /// Runs `change`, turning invalid settings into a message on stderr and exit code 1.
    static func reportingInvalidSettings(_ change: () throws -> Void) throws {
        do {
            try change()
        } catch Installer.Failure.invalidSettings(let file) {
            FileHandle.standardError.write(Data("Not changing \(file): it isn't a valid JSON object.\n".utf8))
            throw ExitCode.failure
        }
    }
}
