import Testing
@testable import ASBCore

private let now: Int64 = 10_000_000
private let claude = ProcessRecord(pid: 42, ppid: 1, start: 1, comm: "claude")
private let shell = ProcessRecord(pid: 43, ppid: 42, start: 2, comm: "/bin/bash")

/// An idle session (pid 42 unless `pid` says otherwise) with these background shells and wakeup.
private func idle(
    shells: [String: Int64] = [:], wakeupAt: Int64? = nil, pid: Int32? = 42, state: String = "idle"
) -> ReconciledSession {
    var file = StateFile(path: "state/s1.json", sessionId: "s1")
    file.state = state
    file.pid = pid
    file.stateSince = now - 120_000
    file.backgroundShells = shells
    file.wakeupAt = wakeupAt
    return ReconciledSession(file)
}

private func shown(_ session: ReconciledSession, processes: [ProcessRecord] = [claude, shell]) -> (String, Int64?) {
    let s = Checks.backgroundWork([session], now: now, processes: processes)[0]
    return (s.shown, s.shownSince)
}

@Test func aShellCountsUntilItIs30MinutesOld() {
    let limit = Checks.backgroundShellLimit
    #expect(shown(idle(shells: ["b1": now - limit + 1])) == ("background", now - limit + 1))
    #expect(shown(idle(shells: ["b1": now - limit])).0 == "idle", "30 minutes is over")
}

@Test func theEarliestCountingShellOrWakeupGivesTheTime() {
    let s = idle(shells: ["old": now - 40 * 60_000, "b1": now - 300_000, "b2": now - 60_000], wakeupAt: now + 60_000)
    #expect(shown(s) == ("background", now - 300_000))
    #expect(shown(idle(shells: ["b1": now - 60_000], wakeupAt: now + 60_000)) == ("background", now - 120_000),
            "went idle before the shell was seen")
}

@Test func shellsNeedABashChildOfTheSessionsProcess() {
    let others = ProcessRecord(pid: 50, ppid: 7, start: 2, comm: "bash")
    #expect(shown(idle(shells: ["b1": now - 60_000]), processes: [claude, others]).0 == "idle")
    #expect(shown(idle(shells: ["b1": now - 60_000], pid: nil)).0 == "idle", "no pid, no process to check")
}

@Test func aWakeupCountsWithoutAnyProcessUntilItIsDue() {
    #expect(shown(idle(wakeupAt: now + 1), processes: []) == ("background", now - 120_000))
    #expect(shown(idle(wakeupAt: now)).0 == "idle", "due now")
}

@Test func aWakeupWithoutAnIdleTimeIsShownSinceNow() {
    var session = idle(wakeupAt: now + 60_000)
    session.file.stateSince = nil
    #expect(shown(session) == ("background", now))
}

@Test func onlyIdleSessionsWaitOnBackgroundWork() {
    for state in ["busy", "waiting", "uncertain"] {
        #expect(shown(idle(shells: ["b1": now - 60_000], wakeupAt: now + 60_000, state: state)).0 == state)
    }
}
