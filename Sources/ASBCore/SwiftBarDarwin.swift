import Foundation

// Reading SwiftBar's own preferences. Tests never do: they pass their own preference to
// `swiftBarDir(environment:home:preference:)`.

extension Installer {
    /// SwiftBar's plugin folder, with a leading `~` expanded: `ASB_SWIFTBAR_DIR` when set (empty means
    /// none), else SwiftBar's `PluginDirectory` preference; nil without SwiftBar.
    ///
    /// - Parameters:
    ///   - environment: Holds the override, and the `PATH` to find `defaults` on.
    ///   - home: The home directory `~` stands for.
    public static func swiftBarDir(environment: [String: String], home: String) -> String? {
        swiftBarDir(environment: environment, home: home, preference: swiftBarPreference)
    }

    /// SwiftBar's `PluginDirectory` preference, read with `defaults`; nil when it isn't set.
    static func swiftBarPreference(_ environment: [String: String]) -> String? {
        let defaults = ProcessRunner(environment: environment).resolve("defaults") ?? "/usr/bin/defaults"
        return Herdr.run(defaults, ["read", "com.ameba.SwiftBar", "PluginDirectory"], timeout: 2)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
