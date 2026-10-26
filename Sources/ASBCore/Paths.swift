import Foundation

/// Where things live. Environment variables override the defaults (used by tests and custom setups).
public struct Paths: Sendable, Equatable {
    public var home: String
    public var configFile: String
    /// Set when the environment overrides the state dir; it then wins over the config file.
    public var stateDirOverride: String?
    public var registryDir: String

    public init(home: String, configFile: String, stateDirOverride: String? = nil, registryDir: String) {
        self.home = home
        self.configFile = configFile
        self.stateDirOverride = stateDirOverride
        self.registryDir = registryDir
    }

    /// `home` defaults to `$HOME`, then the account's home directory. (NSHomeDirectory alone would ignore
    /// `$HOME`, so tests that move it couldn't keep asb out of the real one.)
    public static func from(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String? = nil
    ) -> Paths {
        func env(_ key: String) -> String? {
            guard let value = environment[key], !value.isEmpty else { return nil }
            return value
        }
        let home = home ?? env("HOME") ?? NSHomeDirectory()
        return Paths(
            home: home,
            configFile: env("CLAUDE_STATUSBAR_CONFIG") ?? "\(home)/.config/swiftbar-claudecode-minimal/config",
            stateDirOverride: env("CLAUDE_STATUSBAR_STATE_DIR"),
            registryDir: env("CLAUDE_STATUSBAR_REGISTRY_DIR") ?? "\(home)/.claude/sessions"
        )
    }

    /// Where `asb install` keeps the asb the hooks run.
    public var stableBinary: String { "\(home)/Library/Application Support/agentic-status-bar/bin/asb" }

    /// The login item that "Start SwiftBar at login" adds.
    public var loginItemFile: String { "\(home)/Library/LaunchAgents/swiftbar-claudecode-minimal.start-swiftbar.plist" }

    /// The default state dir, used when neither the environment nor the config sets one.
    public var defaultStateDir: String { "\(home)/.claude/swiftbar-claudecode-minimal" }

    /// Expands a leading `~` to the home directory.
    public func expandingHome(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// The state dir: the environment, else the config's `state_dir`, else the default.
    public func stateDir(config: Config) -> String {
        expandingHome(stateDirOverride ?? config.stateDir ?? defaultStateDir)
    }
}
