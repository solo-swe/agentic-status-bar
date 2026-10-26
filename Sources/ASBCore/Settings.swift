import Foundation

/// Adding and removing our hooks in Claude Code's settings (~/.claude/settings.json), leaving every
/// other setting and hook as it is, in its order.
public enum HookSettings {
    /// Every hook entry we add ends with this, so uninstall finds exactly ours.
    public static let marker = "# agentic-status-bar"
    /// The shell era's entries, replaced on install and removed on uninstall.
    public static let oldMarker = "# swiftbar-claudecode-minimal"
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop",
        "SubagentStart", "SubagentStop", "SessionEnd",
    ]

    /// The hook command for an asb binary at `path`.
    public static func command(asb path: String) -> String {
        "'\(path)' hook \(marker)"
    }

    static func isOurs(_ hook: OrderedJSON, markers: [String]) -> Bool {
        guard let command = hook["command"]?.stringValue else { return false }
        return markers.contains { command.hasSuffix($0) }
    }

    /// Adds one async hook per event that doesn't have ours yet, after removing the shell era's entries.
    public static func install(_ settings: OrderedJSON, command: String) -> OrderedJSON {
        var s = uninstall(settings, markers: [oldMarker])
        var hooks = s["hooks"] ?? .object([])
        guard hooks.isObject else { return s }
        for event in events {
            let groups = hooks[event]?.arrayValue ?? []
            let hasOurs = groups.contains { ($0["hooks"]?.arrayValue ?? []).contains { isOurs($0, markers: [marker]) } }
            if hasOurs { continue }
            let entry: OrderedJSON = .object([
                ("hooks", .array([.object([
                    ("type", .string("command")), ("command", .string(command)),
                    ("async", .bool(true)), ("timeout", .number("10")),
                ])])),
            ])
            hooks[event] = .array(groups + [entry])
        }
        s["hooks"] = hooks
        return s
    }

    /// Removes our hook entries, then groups and events left empty by that, then `hooks` if empty.
    /// Groups that also hold other hooks keep those.
    public static func uninstall(_ settings: OrderedJSON, markers: [String] = [marker, oldMarker]) -> OrderedJSON {
        guard case .object(let events)? = settings["hooks"] else { return settings }
        var kept: [(String, OrderedJSON)] = []
        for (event, value) in events {
            guard case .array(let groups) = value else {
                kept.append((event, value))
                continue
            }
            let remaining: [OrderedJSON] = groups.compactMap { group in
                guard case .array(let hooks)? = group["hooks"], hooks.contains(where: { isOurs($0, markers: markers) }) else {
                    return group
                }
                let others = hooks.filter { !isOurs($0, markers: markers) }
                if others.isEmpty { return nil }
                var g = group
                g["hooks"] = .array(others)
                return g
            }
            if !remaining.isEmpty || groups.isEmpty { kept.append((event, .array(remaining))) }
        }
        var s = settings
        s["hooks"] = kept.isEmpty ? nil : .object(kept)
        return s
    }

    /// How many of our hook entries the settings hold.
    public static func count(_ settings: OrderedJSON, markers: [String] = [marker]) -> Int {
        guard case .object(let events)? = settings["hooks"] else { return 0 }
        return events.reduce(0) { total, pair in
            total + (pair.1.arrayValue ?? []).reduce(0) { sum, group in
                sum + (group["hooks"]?.arrayValue ?? []).filter { isOurs($0, markers: markers) }.count
            }
        }
    }
}
