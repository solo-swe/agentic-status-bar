import ArgumentParser
import ASBCore
import Foundation

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Add the hooks to Claude Code's settings. Safe to run again."
    )

    func run() throws {
        do {
            try Setup.installer().install()
        } catch Installer.Failure.invalidSettings(let file) {
            FileHandle.standardError.write(Data("Not changing \(file): it isn't a valid JSON object.\n".utf8))
            throw ExitCode.failure
        }
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
        do {
            try installer.uninstall(purge: purge) {
                guard isatty(0) == 1 else { return false }
                print("Also delete \(installer.stateDir) and \(installer.configFile)? [y/N] ", terminator: "")
                return ["y", "yes"].contains((readLine() ?? "").lowercased())
            }
        } catch Installer.Failure.invalidSettings(let file) {
            FileHandle.standardError.write(Data("Not changing \(file): it isn't a valid JSON object.\n".utf8))
            throw ExitCode.failure
        }
    }
}

enum Setup {
    /// An installer for this machine. Overrides: ASB_SETTINGS (settings file),
    /// ASB_SWIFTBAR_DIR (SwiftBar's plugin folder, where an old link of ours is removed).
    static func installer() -> Installer {
        let env = ProcessInfo.processInfo.environment
        let paths = Paths.from(environment: env)
        let config = Config.load(paths)
        let executable = URL(fileURLWithPath: CommandLine.executablePath).resolvingSymlinksInPath().path
        var installer = Installer(
            settingsFile: env["ASB_SETTINGS"] ?? "\(paths.home)/.claude/settings.json",
            stableBinary: paths.stableBinary,
            sourceBinary: executable,
            swiftBarDir: swiftBarDir(env, home: paths.home),
            loginItemFile: paths.loginItemFile,
            stateDir: paths.stateDir(config: config),
            configFile: paths.configFile)
        installer.old = .init(stateDir: paths.oldStateDir, configFile: paths.oldConfigFile, loginItemFile: paths.oldLoginItemFile)
        return installer
    }

    /// SwiftBar's plugin folder: the override, or SwiftBar's preference; nil without SwiftBar.
    static func swiftBarDir(_ env: [String: String], home: String) -> String? {
        if let dir = env["ASB_SWIFTBAR_DIR"] { return dir.isEmpty ? nil : expand(dir, home: home) }
        if let dir = defaultsPluginDirectory(env), !dir.isEmpty { return expand(dir, home: home) }
        return nil
    }

    static func defaultsPluginDirectory(_ env: [String: String]) -> String? {
        let defaults = ProcessRunner(environment: env).resolve("defaults") ?? "/usr/bin/defaults"
        return Herdr.run(defaults, ["read", "com.ameba.SwiftBar", "PluginDirectory"], timeout: 2)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func expand(_ path: String, home: String) -> String {
        Paths(home: home, configFile: "", registryDir: "").expandingHome(path)
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
