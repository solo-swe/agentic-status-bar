import Foundation

/// Everything a snapshot is computed from, as plain data. `asb snapshot` and the app
/// gather it from disk and the system; the conformance suite loads it from case files.
public struct SnapshotInputs: Sendable {
    /// Epoch milliseconds.
    public var now: Int64
    /// For local times (mute text, midnight).
    public var timeZone: TimeZone
    /// Session state files: path and raw contents.
    public var stateFiles: [RawFile]
    /// Claude Code's session registry files: path and raw contents.
    public var registryFiles: [RawFile]
    /// Transcripts by the path a state file refers to.
    public var transcripts: [String: TranscriptInput]
    public var processes: [ProcessRecord]
    /// Raw output of `herdr agent list`; nil when herdr isn't installed or didn't answer.
    public var herdrList: String?
    public var herdrInstalled: Bool
    /// Raw config file contents; nil when there is none.
    public var configText: String?
    /// Raw mutes file contents; nil when there is none.
    public var mutesText: String?

    public init(
        now: Int64, timeZone: TimeZone = .current, stateFiles: [RawFile] = [],
        registryFiles: [RawFile] = [], transcripts: [String: TranscriptInput] = [:],
        processes: [ProcessRecord] = [], herdrList: String? = nil, herdrInstalled: Bool = false,
        configText: String? = nil, mutesText: String? = nil
    ) {
        self.now = now
        self.timeZone = timeZone
        self.stateFiles = stateFiles
        self.registryFiles = registryFiles
        self.transcripts = transcripts
        self.processes = processes
        self.herdrList = herdrList
        self.herdrInstalled = herdrInstalled
        self.configText = configText
        self.mutesText = mutesText
    }
}

public struct RawFile: Sendable, Equatable {
    public var path: String
    public var contents: Data

    public init(path: String, contents: Data) {
        self.path = path
        self.contents = contents
    }
}

public struct TranscriptInput: Sendable, Equatable {
    /// Modification time, epoch milliseconds.
    public var mtime: Int64
    /// The file's contents (the engine reads only the tail).
    public var contents: Data

    public init(mtime: Int64, contents: Data) {
        self.mtime = mtime
        self.contents = contents
    }
}

/// One process, as the checks need it.
public struct ProcessRecord: Sendable, Equatable, Codable {
    public var pid: Int32
    public var ppid: Int32
    /// Start time, epoch seconds.
    public var start: Int64
    /// Executable name or path.
    public var comm: String
    /// Full command line, when known.
    public var args: String?

    public init(pid: Int32, ppid: Int32, start: Int64, comm: String, args: String? = nil) {
        self.pid = pid
        self.ppid = ppid
        self.start = start
        self.comm = comm
        self.args = args
    }
}

/// A snapshot plus the side effects the caller performs.
public struct SnapshotResult: Sendable, Equatable {
    public var snapshot: Snapshot
    /// State files of sessions whose process is gone (check C1); the caller deletes them.
    public var deadFiles: [String]
    /// A registry entry had no `status` field: the caller logs it once.
    public var registrySchemaIssue: Bool

    public init(snapshot: Snapshot, deadFiles: [String] = [], registrySchemaIssue: Bool = false) {
        self.snapshot = snapshot
        self.deadFiles = deadFiles
        self.registrySchemaIssue = registrySchemaIssue
    }
}

/// Computes snapshots. Pure: no file system, clock or process access.
public enum Engine {
    public static func snapshot(_ inputs: SnapshotInputs) -> SnapshotResult {
        let reconciled = reconcile(inputs)

        // Filters, mutes, themes and the menu model are filled in by the core port tasks;
        // until then the snapshot has no rows.
        let header = Snapshot.Header(state: .none, symbol: "sparkle", color: "#C7C7CC,#48484A")
        return SnapshotResult(
            snapshot: Snapshot(generatedAt: inputs.now, invalidFiles: reconciled.invalidCount, header: header),
            deadFiles: reconciled.deadFiles,
            registrySchemaIssue: reconciled.registrySchemaIssue)
    }

    /// The sessions after the reconciliation checks, in state file order.
    public struct Reconciled: Equatable, Sendable {
        public var sessions: [ReconciledSession]
        public var invalidCount: Int
        public var deadFiles: [String]
        public var registrySchemaIssue: Bool
    }

    /// Parses the state files and runs the checks (C1 to C5) on them.
    public static func reconcile(_ inputs: SnapshotInputs) -> Reconciled {
        let config = Config.parse(inputs.configText)
        let parsed = ParsedStates.parse(inputs.stateFiles)
        var (sessions, dead) = Checks.liveness(
            parsed.sessions.map(ReconciledSession.init), processes: inputs.processes, timeZone: inputs.timeZone)
        var schemaIssue = false
        if config.useRegistry {
            (sessions, schemaIssue) = Checks.registry(sessions, entries: RegistryEntry.parse(inputs.registryFiles))
        }
        sessions = Checks.interrupts(sessions, transcripts: inputs.transcripts)
        sessions = Checks.approvedTools(sessions, processes: inputs.processes)
        sessions = Checks.staleness(
            sessions, staleMinutes: config.staleMinutes, now: inputs.now,
            transcripts: inputs.transcripts, processes: inputs.processes)
        return Reconciled(
            sessions: sessions, invalidCount: parsed.invalidCount, deadFiles: dead, registrySchemaIssue: schemaIssue)
    }
}
