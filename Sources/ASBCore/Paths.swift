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
            configFile: env("ASB_CONFIG") ?? "\(home)/.config/agentic-status-bar/config",
            stateDirOverride: env("ASB_STATE_DIR"),
            registryDir: env("ASB_REGISTRY_DIR") ?? "\(home)/.claude/sessions"
        )
    }

    /// Where `asb install` keeps the asb the hooks run.
    public var stableBinary: String { "\(home)/Library/Application Support/agentic-status-bar/bin/asb" }

    /// The login item the SwiftBar plugin's "Start SwiftBar at login" added; install and the app's
    /// Start at login remove it.
    public var loginItemFile: String { "\(home)/Library/LaunchAgents/\(Self.loginItemLabel).plist" }
    public static let loginItemLabel = "agentic-status-bar.start-swiftbar"

    /// The default state dir, used when neither the environment nor the config sets one.
    public var defaultStateDir: String { "\(home)/.claude/agentic-status-bar" }

    /// Where the SwiftBar plugin (Minimalist Claude Code Statusbar) kept things before the rename;
    /// `asb install` moves them.
    public var oldStateDir: String { "\(home)/.claude/swiftbar-claudecode-minimal" }
    public var oldConfigFile: String { "\(home)/.config/swiftbar-claudecode-minimal/config" }
    public var oldLoginItemFile: String { "\(home)/Library/LaunchAgents/swiftbar-claudecode-minimal.start-swiftbar.plist" }

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
