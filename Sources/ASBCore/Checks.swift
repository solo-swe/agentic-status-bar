import Foundation

/// A session on its way through the reconciliation checks (PRD › Reconciliation checks).
/// The checks never change state files; they only decide what to show.
public struct ReconciledSession: Equatable, Sendable {
    public var file: StateFile
    /// The display state: the file's `state`, possibly changed by a check.
    public var shown: String
    /// Since when `shown` holds when a check changed it; nil means the file's `stateSince`.
    public var shownSince: Int64?
    /// Why a waiting session waits: the file's `reason`, or the registry's (C2).
    public var reason: String?
    /// A name the user gave the session in Claude Code (from the registry, C2).
    public var sessionName: String?
    /// Set by check C3: the transcript shows the turn was interrupted.
    public var interrupted = false

    public init(_ file: StateFile) {
        self.file = file
        self.shown = file.state ?? "busy"
        self.reason = file.reason
    }
}

public enum Checks {
    /// C1: a session whose claude process is gone, or whose PID now belongs to a process with a
    /// different start time (a reused PID), is dead. Sessions without a PID are kept.
    /// Returns the live sessions and the paths of the dead ones' files.
    public static func liveness(
        _ sessions: [ReconciledSession], processes: [ProcessRecord], timeZone: TimeZone
    ) -> (alive: [ReconciledSession], dead: [String]) {
        let byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var alive: [ReconciledSession] = []
        var dead: [String] = []
        for session in sessions {
            guard let pid = session.file.pid else {
                alive.append(session)
                continue
            }
            if let process = byPid[pid],
               session.file.procStart.map({ ProcStart.matches($0, seconds: process.start, timeZone: timeZone) }) ?? true {
                alive.append(session)
            } else {
                dead.append(session.file.path)
            }
        }
        return (alive, dead)
    }

    /// Start times (epoch ms) of the children of `pid`.
    static func childStarts(of pid: Int32, in processes: [ProcessRecord], excluding name: String? = nil) -> [Int64] {
        processes.filter { process in
            process.ppid == pid && (name == nil || (process.comm as NSString).lastPathComponent != name)
        }.map { $0.start * 1000 }
    }

    /// C4: a waiting session whose claude process has a child that started after the prompt
    /// appeared ran an approved tool, so it is busy since that child started. Claude Code starts a
    /// `caffeinate` child at the start of every turn; it doesn't count.
    public static func approvedTools(_ sessions: [ReconciledSession], processes: [ProcessRecord]) -> [ReconciledSession] {
        sessions.map { session in
            guard session.shown == "waiting", let pid = session.file.pid else { return session }
            let since = session.shownSince ?? session.file.stateSince ?? 0
            guard let started = childStarts(of: pid, in: processes, excluding: "caffeinate").filter({ $0 > since }).min()
            else { return session }
            var s = session
            s.shown = "busy"
            s.shownSince = started
            return s
        }
    }

    /// Waiting on subagents: a session with running subagents whose own turn ended (idle, with
    /// background agents left) or that is blocked in its Task or Agent tool. Runs after C4 and
    /// before C5. An interrupt (C3) wins: it can stop subagents without a SubagentStop.
    public static func subagents(_ sessions: [ReconciledSession], now: Int64) -> [ReconciledSession] {
        sessions.map { session in
            let tool = session.file.lastTool
            guard !session.file.subagents.isEmpty, !session.interrupted,
                  session.shown == "idle" || (session.shown == "busy" && (tool == "Task" || tool == "Agent"))
            else { return session }
            var s = session
            s.shown = "subagents"
            s.shownSince = session.file.subagents.values.map { $0.since ?? now }.min()
            return s
        }
    }

    /// C5: a busy session (or one waiting on subagents) with no sign of life for longer than
    /// `staleMinutes` is uncertain since its last activity: a hook write, the time its state was
    /// shown from, a transcript write, or a child process starting. 0 turns the check off.
    public static func staleness(
        _ sessions: [ReconciledSession], staleMinutes: Int, now: Int64,
        transcripts: [String: TranscriptInput], processes: [ProcessRecord]
    ) -> [ReconciledSession] {
        guard staleMinutes > 0 else { return sessions }
        return sessions.map { session in
            guard session.shown == "busy" || session.shown == "subagents" else { return session }
            var activity = [session.file.updatedAt ?? 0, session.shownSince ?? 0]
            if readsTranscript(session.file), let path = session.file.transcriptPath, let t = transcripts[path] {
                activity.append(t.mtime)
            }
            if let pid = session.file.pid {
                activity += childStarts(of: pid, in: processes)
            }
            let last = activity.max() ?? 0
            guard now - last > Int64(staleMinutes) * 60_000 else { return session }
            var s = session
            s.shown = "uncertain"
            s.shownSince = last
            return s
        }
    }
}
