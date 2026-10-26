import Foundation

/// Builds the snapshot's header and rows from the checked, filtered and mute-marked sessions
/// (doc/snapshot-schema.md).
public enum MenuModel {
    /// Width of the row label (project — title) before the state column.
    public static let labelWidth = 48

    public struct Context: Sendable {
        public var now: Int64
        public var timeZone: TimeZone
        public var theme: Theme
        public var showSubagents: Bool
        /// herdr terminal titles by session ID.
        public var titles: [String: String]
        public var herdrInstalled: Bool
        public var invalidFiles: Int
        public var activeMutes: Int

        public init(
            now: Int64, timeZone: TimeZone, theme: Theme, showSubagents: Bool = true, titles: [String: String] = [:],
            herdrInstalled: Bool = false, invalidFiles: Int = 0, activeMutes: Int = 0
        ) {
            self.now = now
            self.timeZone = timeZone
            self.theme = theme
            self.showSubagents = showSubagents
            self.titles = titles
            self.herdrInstalled = herdrInstalled
            self.invalidFiles = invalidFiles
            self.activeMutes = activeMutes
        }
    }

    public static func snapshot(_ sessions: [ReconciledSession], _ context: Context) -> Snapshot {
        Snapshot(
            generatedAt: context.now,
            invalidFiles: context.invalidFiles,
            activeMutes: context.activeMutes,
            header: header(sessions, context),
            sessions: rows(sessions, context))
    }

    // MARK: Header

    /// The most urgent state over the sessions that aren't muted, and how many are in it.
    public static func header(_ sessions: [ReconciledSession], _ context: Context) -> Snapshot.Header {
        let theme = context.theme
        func make(_ state: Snapshot.HeaderState, _ count: Int?) -> Snapshot.Header {
            Snapshot.Header(state: state, symbol: theme.symbol(state.rawValue), color: theme.color(state.rawValue), count: count)
        }
        let loud = sessions.filter { !$0.muted }
        func count(_ shown: String) -> Int { loud.filter { $0.shown == shown }.count }

        if context.invalidFiles > 0 { return make(.warning, sessions.count) }
        if count("waiting") > 0 { return make(.waiting, count("waiting")) }
        if count("idle") > 0 { return make(.idle, count("idle")) }
        if count("uncertain") > 0 { return make(.uncertain, count("uncertain")) }
        if !loud.isEmpty { return make(.busy, loud.count) }
        if !sessions.isEmpty { return make(.muted, nil) }
        return make(.none, nil)
    }

    // MARK: Rows

    static func rank(_ s: ReconciledSession) -> Int {
        if s.muted { return 5 }
        switch s.shown {
        case "waiting": return 0
        case "idle": return 1
        case "uncertain": return 2
        case "busy", "subagents": return 3
        default: return 4
        }
    }

    static func since(_ s: ReconciledSession, now: Int64) -> Int64 {
        s.shownSince ?? s.file.stateSince ?? now
    }

    public static func rows(_ sessions: [ReconciledSession], _ context: Context) -> [Snapshot.Session] {
        let ordered = sessions.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            if ra != rb { return ra < rb }
            let (sa, sb) = (since(a.element, now: context.now), since(b.element, now: context.now))
            if sa != sb { return sa < sb }
            return a.offset < b.offset  // stable, like jq's sort_by
        }.map(\.element)
        return ordered.map { row($0, context) }
    }

    static func row(_ s: ReconciledSession, _ context: Context) -> Snapshot.Session {
        let theme = context.theme
        let shown = Snapshot.ShownState(rawValue: s.shown) ?? .busy
        let iconState = s.muted ? "muted" : shown.rawValue
        let start = since(s, now: context.now)
        let project = projectName(s.file.cwd)
        let title = rowTitle(s, titles: context.titles)
        let pane = s.file.herdrPane.flatMap { $0.isEmpty ? nil : $0 }
        let subagents: [Snapshot.Subagent] = context.showSubagents
            ? s.file.subagents.map { id, agent in
                let at = agent.since ?? context.now
                return Snapshot.Subagent(id: id, type: agent.type, since: at, detail: ago(at, now: context.now))
            }.sorted { ($0.since, $0.id) < ($1.since, $1.id) }
            : []
        return Snapshot.Session(
            sessionId: s.file.sessionId,
            project: project,
            title: title,
            cwd: s.file.cwd,
            kind: s.file.kind ?? "interactive",
            shown: shown,
            reason: s.shown == "waiting" ? (s.reason == "question" ? "question" : "permission") : nil,
            since: start,
            label: label(project: project, title: title),
            word: word(s),
            detail: s.muted ? muteText(s, timeZone: context.timeZone) : ago(start, now: context.now),
            muted: s.muted,
            muteUntil: s.muteUntil,
            muteToday: s.muteUntil == nil ? nil : s.muteToday,
            herdrPane: pane,
            termBundleId: s.file.termBundleId,
            transcriptPath: s.file.transcriptPath,
            focusable: context.herdrInstalled && pane != nil,
            symbol: theme.symbol(iconState),
            color: theme.color(iconState),
            subagents: subagents)
    }

    /// The state word shown after the label.
    static func word(_ s: ReconciledSession) -> String {
        switch s.shown {
        case "waiting": return s.reason == "question" ? "question" : "permission"
        case "idle": return "idle"
        case "uncertain": return "no activity"
        case "subagents":
            let n = s.file.subagents.count
            return "waiting on \(n) subagent\(n == 1 ? "" : "s")"
        default: return "working"
        }
    }

    /// Title source, best first: herdr terminal title, a user-given session name, the first prompt.
    static func rowTitle(_ s: ReconciledSession, titles: [String: String]) -> String {
        [titles[s.file.sessionId], s.sessionName, s.file.promptPreview]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    /// The cwd's last path component, or "unknown".
    static func projectName(_ cwd: String?) -> String {
        cwd?.split(separator: "/").last.map(String.init) ?? "unknown"
    }

    /// "project — title", fitted to the label width.
    public static func label(project: String, title: String) -> String {
        noSymbols(fit(title.isEmpty ? project : "\(project) — \(title)"))
    }

    /// Replaces `|` (SwiftBar's parameter separator) and cuts to `width` characters with "…", or pads
    /// with spaces. Counts Unicode scalars, like jq's `length`.
    public static func fit(_ text: String, width: Int = labelWidth) -> String {
        let scalars = Array(text.replacingOccurrences(of: "|", with: "│").unicodeScalars)
        if scalars.count > width {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars.prefix(width - 1))
            return String(view) + "…"
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view) + String(repeating: " ", count: width - scalars.count)
    }

    /// Breaks `:name:` with a zero-width space so SwiftBar doesn't draw it as an SF Symbol.
    static func noSymbols(_ text: String) -> String {
        text.replacing(/:([A-Za-z0-9._-]+):/) { match in ":\u{200B}\(match.1):" }
    }

    /// Time since `t` (epoch ms) as 12s, 4m, 2h or 3d.
    public static func ago(_ t: Int64, now: Int64) -> String {
        let s = max(0, (now - t) / 1000)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    static func muteText(_ s: ReconciledSession, timeZone: TimeZone) -> String {
        if s.muteToday { return "muted today" }
        guard let until = s.muteUntil else { return "muted" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return "muted until \(f.string(from: Date(timeIntervalSince1970: TimeInterval(until) / 1000)))"
    }
}

/// Terminal titles from `herdr agent list`.
public enum HerdrTitles {
    /// Claude session ID → terminal title; an unreadable answer gives no titles.
    public static func parse(_ text: String?) -> [String: String] {
        guard let text, let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let agents = (object["result"] as? [String: Any])?["agents"] as? [[String: Any]]
        else { return [:] }
        var titles: [String: String] = [:]
        for agent in agents where agent["agent"] as? String == "claude" {
            guard let session = (agent["agent_session"] as? [String: Any])?["value"] as? String, !session.isEmpty
            else { continue }
            titles[session] = agent["terminal_title_stripped"] as? String ?? ""
        }
        return titles
    }
}
