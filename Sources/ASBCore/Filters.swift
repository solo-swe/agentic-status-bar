/// The session-type filters (Show › Interactive, Headless, IDE / Desktop). Hidden sessions are left
/// out of the rows and the menu-bar count. Show › Subagents only hides the subagent rows.
public enum Filters {
    /// Whether sessions of `kind` are shown. A session without a kind counts as interactive;
    /// desktop sessions follow the IDE filter; unknown kinds are always shown.
    public static func shows(kind: String?, _ config: Config) -> Bool {
        switch kind ?? "interactive" {
        case "interactive": config.showInteractive
        case "headless": config.showHeadless
        case "ide", "desktop": config.showIDE
        default: true
        }
    }

    public static func apply(_ sessions: [ReconciledSession], _ config: Config) -> [ReconciledSession] {
        sessions.filter { shows(kind: $0.file.kind, config) }
    }
}
