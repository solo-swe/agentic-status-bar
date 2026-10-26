import Foundation
import Testing
@testable import ASBCore

private let la = TimeZone(identifier: "America/Los_Angeles")!
/// "Mon Oct 19 09:12:03 2026" in Los Angeles.
private let claudeStart: Int64 = 1_792_426_323

private func session(_ json: String, _ id: String = "s1") -> ReconciledSession {
    let file = RawFile(path: "state/\(id).json", contents: Data(json.utf8))
    return ReconciledSession(StateFile.parse(file)!)
}

private let claude = ProcessRecord(pid: 4242, ppid: 1, start: claudeStart, comm: "claude")

// MARK: C1 liveness

@Test func c1KeepsASessionWhoseClaudeProcessIsRunning() {
    let s = session(#"{"v":1,"sessionId":"s1","state":"idle","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}"#)
    let (alive, dead) = Checks.liveness([s], processes: [claude], timeZone: la)
    #expect(alive.map(\.file.sessionId) == ["s1"])
    #expect(dead.isEmpty)
}

@Test func c1DropsASessionWhoseProcessIsGone() {
    let s = session(#"{"v":1,"sessionId":"s1","state":"idle","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026"}"#)
    let (alive, dead) = Checks.liveness([s], processes: [], timeZone: la)
    #expect(alive.isEmpty)
    #expect(dead == ["state/s1.json"])
}

@Test func c1TreatsAReusedPidWithADifferentStartTimeAsDead() {
    let s = session(#"{"v":1,"sessionId":"s1","state":"idle","pid":4242,"procStart":"Mon Oct 19 08:00:00 2026"}"#)
    let (alive, dead) = Checks.liveness([s], processes: [claude], timeZone: la)
    #expect(alive.isEmpty)
    #expect(dead == ["state/s1.json"])
}

@Test func c1IgnoresExtraSpacesInStartTimes() {
    let s = session(#"{"v":1,"sessionId":"s1","state":"idle","pid":4242,"procStart":"Mon  Oct 19  09:12:03 2026"}"#)
    #expect(Checks.liveness([s], processes: [claude], timeZone: la).alive.count == 1)
}

@Test func c1KeepsSessionsWithoutARecordedPid() {
    let noPid = session(#"{"v":1,"sessionId":"s1","state":"idle"}"#)
    let nullPid = session(#"{"v":1,"sessionId":"s2","state":"idle","pid":null}"#, "s2")
    #expect(Checks.liveness([noPid, nullPid], processes: [], timeZone: la).alive.count == 2)
}

@Test func c1KeepsAPidWithoutProcStartWhileTheProcessRuns() {
    let s = session(#"{"v":1,"sessionId":"s1","state":"busy","pid":4242}"#)
    #expect(Checks.liveness([s], processes: [claude], timeZone: la).alive.count == 1)
    #expect(Checks.liveness([s], processes: [], timeZone: la).dead == ["state/s1.json"])
}

// MARK: C4 approved tool and C5 staleness

private let now: Int64 = 1_792_891_080_000
private func minutesAgo(_ m: Int64) -> Int64 { now - m * 60_000 }
private func secondsAgo(_ s: Int64) -> Int64 { (now / 1000) - s }  // epoch seconds, for process starts

/// The checks on one live session (pid 4242) merged with `state`.
private func checked(
    _ state: String, children: [ProcessRecord] = [], config: String = "stale_minutes=0",
    transcript: TranscriptInput? = nil
) -> ReconciledSession {
    let base = #""v":1,"sessionId":"s1","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026","cwd":"/x/proj""#
    var inputs = SnapshotInputs(now: now, timeZone: la, configText: config)
    inputs.stateFiles = [RawFile(path: "state/s1.json", contents: Data("{\(base),\(state)}".utf8))]
    inputs.processes = [claude] + children
    if let transcript { inputs.transcripts = ["t.jsonl": transcript] }
    return Engine.reconcile(inputs).sessions[0]
}

private func child(_ pid: Int32, _ comm: String, startedSecondsAgo: Int64, parent: Int32 = 4242) -> ProcessRecord {
    ProcessRecord(pid: pid, ppid: parent, start: secondsAgo(startedSecondsAgo), comm: comm)
}

@Test func c4ShowsAWaitingSessionAsBusyWhenAToolStartedAfterThePrompt() {
    let s = checked(#""state":"waiting","reason":"permission","updatedAt":\#(minutesAgo(1)),"stateSince":\#(minutesAgo(1))"#,
                    children: [child(7001, "/bin/zsh", startedSecondsAgo: 55)])
    #expect(s.shown == "busy")
    #expect(s.shownSince == secondsAgo(55) * 1000)
}

@Test func c4IgnoresChildrenStartedBeforeThePrompt() {
    let s = checked(#""state":"waiting","reason":"permission","updatedAt":\#(minutesAgo(1)),"stateSince":\#(minutesAgo(1))"#,
                    children: [child(7002, "node", startedSecondsAgo: 3600)])
    #expect(s.shown == "waiting")
}

@Test func c4IgnoresCaffeinate() {
    let s = checked(#""state":"waiting","reason":"permission","updatedAt":\#(minutesAgo(1)),"stateSince":\#(minutesAgo(1))"#,
                    children: [child(7003, "/usr/bin/caffeinate", startedSecondsAgo: 55)])
    #expect(s.shown == "waiting")
}

@Test func c4IgnoresChildrenOfOtherProcesses() {
    let s = checked(#""state":"waiting","reason":"permission","updatedAt":\#(minutesAgo(1)),"stateSince":\#(minutesAgo(1))"#,
                    children: [child(7004, "zsh", startedSecondsAgo: 55, parent: 9999)])
    #expect(s.shown == "waiting")
}

@Test func c5MarksABusySessionWithNoActivityPastTheThresholdAsUncertain() {
    let s = checked(#""state":"busy","updatedAt":\#(minutesAgo(45)),"stateSince":\#(minutesAgo(45))"#,
                    config: "stale_minutes=30")
    #expect(s.shown == "uncertain")
    #expect(s.shownSince == minutesAgo(45))
}

@Test func c5LeavesABusySessionAloneWithinTheThreshold() {
    #expect(checked(#""state":"busy","updatedAt":\#(minutesAgo(10))"#, config: "stale_minutes=30").shown == "busy")
}

@Test func c5CountsARecentTranscriptWriteAsActivity() {
    let s = checked(#""state":"busy","updatedAt":\#(minutesAgo(45)),"transcriptPath":"t.jsonl""#,
                    config: "stale_minutes=30",
                    transcript: TranscriptInput(mtime: minutesAgo(1), contents: Data(#"{"type":"assistant"}"#.utf8)))
    #expect(s.shown == "busy")
}

@Test func c5CountsARecentlyStartedChildProcessAsActivity() {
    let s = checked(#""state":"busy","updatedAt":\#(minutesAgo(45))"#,
                    children: [child(7005, "zsh", startedSecondsAgo: 120)], config: "stale_minutes=30")
    #expect(s.shown == "busy")
}

@Test func c5UsesTheConfiguredThresholdAndIsOffAt0() {
    #expect(checked(#""state":"busy","updatedAt":\#(minutesAgo(45))"#, config: "stale_minutes=60").shown == "busy")
    #expect(checked(#""state":"busy","updatedAt":\#(minutesAgo(600))"#, config: "stale_minutes=0").shown == "busy")
    // The default is 30 minutes.
    #expect(checked(#""state":"busy","updatedAt":\#(minutesAgo(45))"#, config: "").shown == "uncertain")
}

@Test func c5NeverMarksWaitingOrIdleSessionsAsStale() {
    #expect(checked(#""state":"waiting","reason":"permission","updatedAt":\#(minutesAgo(300)),"stateSince":\#(minutesAgo(300))"#,
                    config: "stale_minutes=30").shown == "waiting")
    #expect(checked(#""state":"idle","updatedAt":\#(minutesAgo(300))"#, config: "stale_minutes=30").shown == "idle")
}

@Test func c5AppliesToAToolApprovedByC4() {
    // Approved long ago, nothing since: C4 makes it busy, then C5 finds it stale.
    let s = checked(#""state":"waiting","reason":"permission","updatedAt":\#(minutesAgo(90)),"stateSince":\#(minutesAgo(90))"#,
                    children: [child(7006, "zsh", startedSecondsAgo: 80 * 60)], config: "stale_minutes=30")
    #expect(s.shown == "uncertain")
    #expect(s.shownSince == secondsAgo(80 * 60) * 1000)
}

@Test func shownStartsAsTheFileState() {
    #expect(session(#"{"v":1,"sessionId":"s1","state":"waiting"}"#).shown == "waiting")
    #expect(session(#"{"v":1,"sessionId":"s1"}"#).shown == "busy")
}
