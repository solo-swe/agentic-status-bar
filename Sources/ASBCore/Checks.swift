import Foundation

/// A session on its way through the reconciliation checks (PRD › Reconciliation checks).
/// The checks never change state files; they only decide what to show.
public struct ReconciledSession: Equatable, Sendable {
    public var file: StateFile
    /// The display state: the file's `state`, possibly changed by a check.
    public var shown: String
    /// Since when `shown` holds when a check changed it; nil means the file's `stateSince`.
    public var shownSince: Int64?
    /// Set by check C3: the transcript shows the turn was interrupted.
    public var interrupted = false

    public init(_ file: StateFile) {
        self.file = file
        self.shown = file.state ?? "busy"
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
}
