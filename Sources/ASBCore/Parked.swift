extension Checks {
    /// C6: a session its claude process parked is gone from that process. Claude Code moves a
    /// parked session into a background job, which runs as a new session in another process; the
    /// old process keeps running, so C1 keeps its file and no hook event ends it. The registry
    /// entry with the session's PID and session ID then names the job in `parkedJobId`.
    /// Returns the sessions that aren't parked; their files stay (C1 deletes them later).
    public static func parked(
        _ sessions: [ReconciledSession], entries: [Int32: RegistryEntry]
    ) -> [ReconciledSession] {
        sessions.filter { session in
            guard let pid = session.file.pid, let entry = entries[pid] else { return true }
            return entry.sessionId != session.file.sessionId || entry.parkedJobId == nil
        }
    }
}
