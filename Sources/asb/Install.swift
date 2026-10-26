import ArgumentParser
import ASBCore
import Foundation

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Add the hooks to Claude Code's settings and link the SwiftBar plugin. Safe to run again."
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
    /// An installer for this machine. Overrides: CLAUDE_STATUSBAR_SETTINGS (settings file),
    /// CLAUDE_STATUSBAR_SWIFTBAR_DIR (SwiftBar's plugin folder).
    static func installer() -> Installer {
        let env = ProcessInfo.processInfo.environment
        let paths = Paths.from(environment: env)
        let config = Config.load(paths)
        let executable = URL(fileURLWithPath: CommandLine.executablePath).resolvingSymlinksInPath().path
        return Installer(
            settingsFile: env["CLAUDE_STATUSBAR_SETTINGS"] ?? "\(paths.home)/.claude/settings.json",
            stableBinary: paths.stableBinary,
            sourceBinary: executable,
            pluginFile: pluginFile(near: executable),
            swiftBarDir: swiftBarDir(env, home: paths.home),
            loginItemFile: paths.loginItemFile,
            stateDir: paths.stateDir(config: config),
            configFile: paths.configFile)
    }

    /// The SwiftBar plugin file of the repo asb was built in (walking up from the binary), if any.
    static func pluginFile(near executable: String) -> String? {
        var dir = (executable as NSString).deletingLastPathComponent
        for _ in 0..<5 {
            let candidate = (dir as NSString).appendingPathComponent("swiftbar/\(Installer.pluginName)")
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// SwiftBar's plugin folder: the override, SwiftBar's preference, or (on a terminal) asked for.
    static func swiftBarDir(_ env: [String: String], home: String) -> String? {
        if let dir = env["CLAUDE_STATUSBAR_SWIFTBAR_DIR"] { return dir.isEmpty ? nil : expand(dir, home: home) }
        if let dir = defaultsPluginDirectory(env), !dir.isEmpty { return expand(dir, home: home) }
        guard isatty(0) == 1 else { return nil }
        print("SwiftBar has no plugin folder yet. Folder to use (empty to skip): ", terminator: "")
        let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces)
        return answer.isEmpty ? nil : expand(answer, home: home)
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
