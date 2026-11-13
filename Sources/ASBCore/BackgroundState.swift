extension Checks {
    /// How long a background shell keeps a session out of idle: a `Monitor` expires within 30 minutes,
    /// while a dev server left running in the background would otherwise hide the idle state for hours.
    /// A shell that ends wakes the session, and the next Stop drops it; this limit bounds anything missed.
    public static let backgroundShellLimit: Int64 = 30 * 60_000

    /// Waiting on background work: an idle session (no prompt open, no subagent running) that has a
    /// background shell or monitor first seen under `backgroundShellLimit` ago, or a scheduled wakeup
    /// still ahead. Runs after the subagents state and before C5, which leaves it alone. Shown since the
    /// earliest such shell, or since the session went idle for a wakeup.
    ///
    /// There is no process check: background shells run in the user's login shell through Claude
    /// Code's wrapper, indistinguishable by name from a status line script or a tool's shell.
    public static func backgroundWork(_ sessions: [ReconciledSession], now: Int64) -> [ReconciledSession] {
        sessions.map { session in
            guard session.shown == "idle" else { return session }
            let file = session.file
            var starts = file.backgroundShells.values.filter { now - $0 < backgroundShellLimit }
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
}
