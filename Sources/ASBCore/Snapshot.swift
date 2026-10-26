import Foundation

/// What every front end reads: the reconciled sessions in display order, plus the
/// menu-bar header. Produced by `asb snapshot --json`; see doc/snapshot-schema.md.
public struct Snapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Epoch milliseconds when the snapshot was made; every `detail` text is relative to it.
    public var generatedAt: Int64
    /// State files that couldn't be read (corrupt, not an object, or a newer schema).
    public var invalidFiles: Int
    /// Projects with an active mute, including ones without a running session.
    public var activeMutes: Int
    public var header: Header
    public var sessions: [Session]

    public init(
        version: Int = Snapshot.currentVersion, generatedAt: Int64, invalidFiles: Int = 0,
        activeMutes: Int = 0, header: Header, sessions: [Session] = []
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.invalidFiles = invalidFiles
        self.activeMutes = activeMutes
        self.header = header
        self.sessions = sessions
    }

    /// The menu-bar item: the most urgent state and the number of sessions in it.
    public struct Header: Codable, Equatable, Sendable {
        public var state: HeaderState
        /// SF Symbol name.
        public var symbol: String
        /// `#RRGGBB,#RRGGBB` (light, dark).
        public var color: String
        /// Sessions in `state`; nil when no number is shown (muted, none).
        public var count: Int?

        public init(state: HeaderState, symbol: String, color: String, count: Int? = nil) {
            self.state = state
            self.symbol = symbol
            self.color = color
            self.count = count
        }
    }

    public enum HeaderState: String, Codable, Sendable {
        case warning, waiting, idle, uncertain, busy, muted, none
    }

    /// One session row.
    public struct Session: Codable, Equatable, Sendable {
        public var sessionId: String
        /// The cwd's last path component, or "unknown".
        public var project: String
        /// herdr terminal title, user-given session name or prompt preview; "" when none.
        public var title: String
        public var cwd: String?
        public var kind: String
        public var shown: ShownState
        public var reason: String?
        /// Epoch ms since the session has been in `shown`.
        public var since: Int64
        /// "project — title", fitted to the row width.
        public var label: String
        /// The state word: permission, question, idle, no activity, waiting on N subagents, working.
        public var word: String
        /// Time in state ("2m") or the mute text ("muted until 18:40", "muted today").
        public var detail: String
        public var muted: Bool
        public var muteUntil: Int64?
        public var muteToday: Bool?
        public var herdrPane: String?
        public var termBundleId: String?
        public var transcriptPath: String?
        /// Whether a click can focus the session (it runs in a herdr pane and herdr is installed).
        public var focusable: Bool
        public var symbol: String
        public var color: String
        public var subagents: [Subagent]

        public init(
            sessionId: String, project: String, title: String = "", cwd: String? = nil,
            kind: String = "interactive", shown: ShownState, reason: String? = nil, since: Int64,
            label: String, word: String, detail: String, muted: Bool = false, muteUntil: Int64? = nil,
            muteToday: Bool? = nil, herdrPane: String? = nil, termBundleId: String? = nil,
            transcriptPath: String? = nil, focusable: Bool = false, symbol: String, color: String,
            subagents: [Subagent] = []
        ) {
            self.sessionId = sessionId
            self.project = project
            self.title = title
            self.cwd = cwd
            self.kind = kind
            self.shown = shown
            self.reason = reason
            self.since = since
            self.label = label
            self.word = word
            self.detail = detail
            self.muted = muted
            self.muteUntil = muteUntil
            self.muteToday = muteToday
            self.herdrPane = herdrPane
            self.termBundleId = termBundleId
            self.transcriptPath = transcriptPath
            self.focusable = focusable
            self.symbol = symbol
            self.color = color
            self.subagents = subagents
        }
    }

    /// A session's display state after the checks.
    public enum ShownState: String, Codable, Sendable {
        case waiting, idle, uncertain, busy, subagents
    }

    /// A running subagent, shown indented under its parent.
    public struct Subagent: Codable, Equatable, Sendable {
        public var id: String
        public var type: String
        public var since: Int64
        /// Time running ("12s").
        public var detail: String

        public init(id: String, type: String, since: Int64, detail: String) {
            self.id = id
            self.type = type
            self.since = since
            self.detail = detail
        }
    }

    /// Stable JSON: sorted keys, absent optionals left out.
    public func encodedJSON(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
