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

@Test func shownStartsAsTheFileState() {
    #expect(session(#"{"v":1,"sessionId":"s1","state":"waiting"}"#).shown == "waiting")
    #expect(session(#"{"v":1,"sessionId":"s1"}"#).shown == "busy")
}
