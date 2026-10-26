/// Renders a snapshot in SwiftBar's plugin output format: the menu-bar line, `---`, the rows with
/// their submenus, then the Show and Settings sections. Exactly what the shell plugin printed.
public enum SwiftBarRenderer {
    /// What menu items run.
    public enum Target: Sendable {
        /// The SwiftBar plugin file: `bash="<path>" param1=<action> param2=<arg>`.
        case plugin(String)
        /// asb itself: `bash="<path>" param1=action param2=<action> param3=<arg>`.
        case asb(String)

        func command(_ args: [String]) -> String {
            switch self {
            case .plugin(let path): return Self.format(path, args)
            case .asb(let path): return Self.format(path, ["action"] + args)
            }
        }

        private static func format(_ path: String, _ args: [String]) -> String {
            let params = args.enumerated().map { "param\($0.offset + 1)=\($0.element)" }
            return (["bash=\"\(path)\""] + params).joined(separator: " ")
        }
    }

    public struct Settings: Sendable {
        public var config: Config
        /// Whether the "Start SwiftBar at login" item is installed.
        public var startsAtLogin: Bool

        public init(config: Config, startsAtLogin: Bool) {
            self.config = config
            self.startsAtLogin = startsAtLogin
        }
    }

    public static func render(_ snapshot: Snapshot, settings: Settings, target: Target) -> String {
        var lines = [header(snapshot.header), "---"]
        if snapshot.invalidFiles > 0 {
            lines.append("\(snapshot.invalidFiles) state file(s) could not be read | color=gray")
        }
        if snapshot.sessions.isEmpty {
            lines.append("No Claude Code sessions | color=gray")
        }
        for session in snapshot.sessions {
            lines += row(session, target: target)
        }
        lines.append("---")
        lines += footer(activeMutes: snapshot.activeMutes, settings: settings, target: target)
        lines += ["---", "Refresh | refresh=true"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The menu-bar line: the symbol inline (SwiftBar colors only inline symbols), then the count.
    static func header(_ h: Snapshot.Header) -> String {
        let count = h.count.map { " \($0)" } ?? ""
        return ":\(h.symbol):\(count) | sfcolor=\(h.color) color=\(h.color)"
    }

    static func row(_ s: Snapshot.Session, target: Target) -> [String] {
        func action(_ text: String, _ name: String) -> String {
            "--\(text) | \(target.command([name, s.sessionId])) terminal=false"
        }
        let click = s.focusable ? " \(target.command(["focus", s.sessionId])) terminal=false" : ""
        var lines = [":\(s.symbol): \(s.label)  \(s.word) · \(s.detail) | font=Menlo size=12 sfcolor=\(s.color)\(click)"]
        if !s.focusable {
            lines.append("--Not in herdr: click to focus is unavailable | color=gray")
        }
        if s.cwd != nil {
            if s.muteUntil != nil {
                lines.append(action("Unmute project", "unmute") + " refresh=true")
            } else {
                lines.append(action("Mute project for 1 hour", "mute-hour") + " refresh=true")
                lines.append(action("Mute project for today", "mute-today") + " refresh=true")
            }
        }
        lines.append(action("Copy session ID", "copy-id"))
        lines.append(action("Copy working directory", "copy-cwd"))
        if s.cwd != nil { lines.append(action("Open folder in Finder", "open-folder")) }
        if s.transcriptPath != nil { lines.append(action("Reveal transcript", "reveal-transcript")) }
        for agent in s.subagents {
            let label = MenuModel.fit("↳ subagent: \(agent.type)")
            lines.append("  \(label)  working · \(agent.detail) | font=Menlo size=12 color=gray")
        }
        return lines
    }

    static func footer(activeMutes: Int, settings: Settings, target: Target) -> [String] {
        let c = settings.config
        func run(_ args: [String]) -> String { " | \(target.command(args)) terminal=false refresh=true" }
        func check(_ on: Bool) -> String { on ? " checked=true" : "" }
        func toggle(_ text: String, _ key: String, _ on: Bool) -> String { text + run(["toggle", key]) + check(on) }
        func stale(_ text: String, _ minutes: Int) -> String {
            "----\(text)" + run(["set", "stale_minutes", "\(minutes)"]) + check(c.staleMinutes == minutes)
        }
        func theme(_ text: String, _ name: String) -> String {
            "----\(text)" + run(["set", "theme", name]) + check(c.theme == name)
        }

        var lines: [String] = []
        if activeMutes > 0 { lines.append("Unmute all projects" + run(["unmute-all"])) }
        lines += [
            "Show | color=gray",
            toggle("Interactive", "show_interactive", c.showInteractive),
            toggle("Headless (claude -p)", "show_headless", c.showHeadless),
            toggle("Subagents", "show_subagents", c.showSubagents),
            toggle("IDE / Desktop", "show_ide", c.showIDE),
            "Settings…",
            "--Start SwiftBar at login" + run(["login"]) + check(settings.startsAtLogin),
            "--Theme",
            theme("Default", "default"),
            theme("Monochrome", "monochrome"),
            theme("High contrast", "high_contrast"),
            "-------",
            "----Customize icons and colors in the config file…" + run(["reveal-config"]),
            "--Mark busy sessions as uncertain after",
            stale("10 minutes", 10),
            stale("30 minutes", 30),
            stale("60 minutes", 60),
            stale("Never", 0),
            "--" + toggle("Refresh instantly on changes", "instant_refresh", c.instantRefresh),
            "--" + toggle("Use Claude Code session registry", "use_registry", c.useRegistry),
            "--" + toggle("Store prompt previews", "store_prompt_preview", c.storePromptPreview),
            "--Reveal config file" + run(["reveal-config"]),
        ]
        return lines
    }
}
