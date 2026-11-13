import Foundation

extension Checks {
    /// How long a background shell keeps a session out of idle: a `Monitor` expires within 30 minutes,
    /// while a dev server left running in the background would otherwise hide the idle state for hours.
    public static let backgroundShellLimit: Int64 = 30 * 60_000

    /// Waiting on background work: an idle session (no prompt open, no subagent running) that has a
    /// background shell or monitor first seen under `backgroundShellLimit` ago while its claude process
    /// still has a `bash` child (no child, no shell), or a scheduled wakeup still ahead. Runs after the
    /// subagents state and before C5, which leaves it alone. Shown since the earliest such shell, or
    /// since the session went idle for a wakeup.
    public static func backgroundWork(
        _ sessions: [ReconciledSession], now: Int64, processes: [ProcessRecord]
    ) -> [ReconciledSession] {
        sessions.map { session in
            guard session.shown == "idle" else { return session }
            let file = session.file
            var starts: [Int64] = []
            if let pid = file.pid, hasShellChild(pid, in: processes) {
                starts += file.backgroundShells.values.filter { now - $0 < backgroundShellLimit }
            }
            if let wakeup = file.wakeupAt, wakeup > now {
                starts.append(session.shownSince ?? file.stateSince ?? now)
            }
            guard let since = starts.min() else { return session }
            var s = session
            s.shown = "background"
            s.shownSince = since
            return s
        }
    }

    /// Whether `pid` has a `bash` child: background shells and monitors run as one.
    static func hasShellChild(_ pid: Int32, in processes: [ProcessRecord]) -> Bool {
        processes.contains { $0.ppid == pid && ($0.comm as NSString).lastPathComponent == "bash" }
    }
}
