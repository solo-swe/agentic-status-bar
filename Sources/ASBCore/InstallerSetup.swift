import Foundation

extension Installer {
    /// An installer for this machine's paths, as `asb install` and the app build it: `HOME` and the
    /// `ASB_*` overrides of `Paths`, `ASB_SETTINGS` for Claude Code's settings file, and the old SwiftBar
    /// plugin's paths to move.
    ///
    /// - Parameters:
    ///   - environment: Where the paths come from.
    ///   - sourceBinary: The asb to copy to the stable path.
    ///   - swiftBarDir: SwiftBar's plugin folder (`swiftBarDir(environment:home:)`), or nil to leave an
    ///     old link there alone.
    ///
    /// ```swift
    /// let environment = ProcessInfo.processInfo.environment
    /// let installer = Installer.forMachine(environment: environment, sourceBinary: "/path/to/asb", swiftBarDir: nil)
    /// try installer.install()
    /// ```
    public static func forMachine(environment: [String: String], sourceBinary: String, swiftBarDir: String?) -> Installer {
        let paths = Paths.from(environment: environment)
        var installer = Installer(
            settingsFile: environment["ASB_SETTINGS"] ?? "\(paths.home)/.claude/settings.json",
            stableBinary: paths.stableBinary,
            sourceBinary: sourceBinary,
            swiftBarDir: swiftBarDir,
            loginItemFile: paths.loginItemFile,
            stateDir: paths.stateDir(config: Config.load(paths)),
            configFile: paths.configFile)
        installer.old = .init(stateDir: paths.oldStateDir, configFile: paths.oldConfigFile, loginItemFile: paths.oldLoginItemFile)
        return installer
    }

    /// `swiftBarDir(environment:home:)` with SwiftBar's `PluginDirectory` preference read by `preference`.
    static func swiftBarDir(
        environment: [String: String], home: String, preference: ([String: String]) -> String?
    ) -> String? {
        let expand = { Paths(home: home, configFile: "", registryDir: "").expandingHome($0) }
        if let dir = environment["ASB_SWIFTBAR_DIR"] { return dir.isEmpty ? nil : expand(dir) }
        if let dir = preference(environment), !dir.isEmpty { return expand(dir) }
        return nil
    }
}

/// Where the running executable is.
public enum ExecutablePath {
    /// The absolute path, with symlinks resolved, of the executable started as `argv0` (`argv[0]`): as
    /// given when absolute, relative to `currentDirectory` when it contains a slash, else the first
    /// executable match in the `PATH` directories `searchPath` lists, since the shell found it there.
    ///
    /// ```swift
    /// ExecutablePath.resolve("asb", currentDirectory: "/tmp", searchPath: "/opt/bin:/usr/bin")
    /// // "/opt/bin/asb" when that file is executable
    /// ```
    public static func resolve(_ argv0: String, currentDirectory: String, searchPath: String?) -> String {
        URL(fileURLWithPath: absolute(argv0, currentDirectory: currentDirectory, searchPath: searchPath))
            .resolvingSymlinksInPath().path
    }

    static func absolute(_ argv0: String, currentDirectory: String, searchPath: String?) -> String {
        if argv0.hasPrefix("/") { return argv0 }
        if argv0.contains("/") {
            return URL(fileURLWithPath: currentDirectory).appendingPathComponent(argv0).standardized.path
        }
        let dirs = (searchPath ?? "").split(separator: ":")
        return dirs.map { "\($0)/\(argv0)" }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? argv0
    }
}
