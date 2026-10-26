import Foundation

/// Settings from the config file (`key=value` lines). See doc/state-file-schema.md › Config file.
public struct Config: Equatable, Sendable {
    /// Menu-bar states a theme gives an icon and a color; `icon_<state>` and `color_<state>` override one.
    public static let themeStates = ["waiting", "idle", "uncertain", "busy", "subagents", "muted", "none", "warning"]

    public static let keys: [String] = [
        "show_interactive", "show_headless", "show_subagents", "show_ide", "stale_minutes", "use_registry",
        "instant_refresh", "icon", "store_prompt_preview", "state_dir", "theme",
        "notify_waiting", "notify_idle", "notify_delay_seconds", "notify_sound",
    ] + themeStates.map { "icon_\($0)" } + themeStates.map { "color_\($0)" }

    public var showInteractive = true
    public var showHeadless = true
    public var showSubagents = true
    public var showIDE = true
    /// Minutes without activity before a busy session counts as uncertain; 0 = off.
    public var staleMinutes = 30
    public var useRegistry = true
    public var instantRefresh = true
    public var storePromptPreview = true
    /// Older shortcut for the busy and empty icon; "" = from the theme.
    public var icon = ""
    /// From the config file, before `~` expansion; nil = default (see `Paths.stateDir`).
    public var stateDir: String?
    public var theme = "default"
    /// Per-state overrides, keyed by state; only set entries are present.
    public var iconOverrides: [String: String] = [:]
    public var colorOverrides: [String: String] = [:]
    /// App notifications: when a session waits on you, when one goes idle, after how long, with a sound.
    public var notifyWaiting = true
    public var notifyIdle = false
    public var notifyDelaySeconds = 10
    public var notifySound = true

    public init() {}

    /// Parses config file text; nil (no file) gives the defaults. Unknown keys and invalid values are ignored.
    public static func parse(_ text: String?) -> Config {
        var config = Config()
        guard let text else { return config }
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq])
            let value = String(line[line.index(after: eq)...])
            guard isKey(key), isValid(value, for: key) else { continue }
            config.apply(key, value)
        }
        return config
    }

    /// Loads the config file, or the defaults when it doesn't exist or can't be read.
    public static func load(_ paths: Paths) -> Config {
        parse(try? String(contentsOfFile: paths.configFile, encoding: .utf8))
    }

    public static func isKey(_ key: String) -> Bool { keys.contains(key) }

    /// Values are plain words or paths: letters, digits and `_ . / ~ -`. Colors (`color_*`) are `#RRGGBB`,
    /// a `#RRGGBB,#RRGGBB` light,dark pair, or empty.
    public static func isValid(_ value: String, for key: String) -> Bool {
        if key.hasPrefix("color_") {
            if value.isEmpty { return true }
            let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            return (1...2).contains(parts.count) && parts.allSatisfy(isHexColor)
        }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_./~-".unicodeScalars.contains(scalar))
        }
    }

    private static func isHexColor(_ s: Substring) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy(\.isHexDigit)
    }

    private mutating func apply(_ key: String, _ value: String) {
        let on = value == "1"
        switch key {
        case "show_interactive": showInteractive = on
        case "show_headless": showHeadless = on
        case "show_subagents": showSubagents = on
        case "show_ide": showIDE = on
        case "stale_minutes": if let n = Int(value), n >= 0 { staleMinutes = n }
        case "use_registry": useRegistry = on
        case "instant_refresh": instantRefresh = on
        case "store_prompt_preview": storePromptPreview = on
        case "icon": icon = value
        case "state_dir": stateDir = value.isEmpty ? nil : value
        case "theme": theme = value
        case "notify_waiting": notifyWaiting = on
        case "notify_idle": notifyIdle = on
        case "notify_delay_seconds": if let n = Int(value), n >= 0 { notifyDelaySeconds = n }
        case "notify_sound": notifySound = on
        default:
            if key.hasPrefix("icon_") {
                iconOverrides[String(key.dropFirst(5))] = value.isEmpty ? nil : value
            } else if key.hasPrefix("color_") {
                colorOverrides[String(key.dropFirst(6))] = value.isEmpty ? nil : value
            }
        }
    }

    /// Sets one key in the config file, keeping the other lines; creates the file and its directory if
    /// needed. Returns false, changing nothing, for an unknown key or an invalid value.
    @discardableResult
    public static func set(_ key: String, _ value: String, in file: String) throws -> Bool {
        guard isKey(key), isValid(value, for: key) else { return false }
        let existing = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        var lines = existing.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { $0.hasPrefix("\(key)=") }
        lines.append("\(key)=\(value)")
        let url = URL(fileURLWithPath: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
        return true
    }
}
