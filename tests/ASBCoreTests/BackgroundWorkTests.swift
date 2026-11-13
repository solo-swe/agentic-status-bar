import Foundation
import Testing
@testable import ASBCore

private let payloads = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/payloads")
private let utc = TimeZone(identifier: "UTC")!

private func payload(_ name: String) throws -> HookPayload {
    try #require(HookPayload.parse(Data(contentsOf: payloads.appendingPathComponent("\(name).json"))))
}

/// The state after `payload` is applied to `state` at `t` (also its start time, unless `started` says otherwise).
private func apply(_ payload: HookPayload, to state: [String: Any]?, at t: Int64, started: Int64? = nil) -> [String: Any]? {
    guard case .write(let s) = HookEvents.apply(
        payload, to: state, now: t, started: started ?? t, storePromptPreview: true, timeZone: utc)
    else { return state }
    return s
}

private func shells(_ state: [String: Any]?) -> [String: Int64] {
    (state?["backgroundShells"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.int64Value }
}

private func wakeup(_ state: [String: Any]?) -> Int64? { (state?["wakeupAt"] as? NSNumber)?.int64Value }

/// Epoch ms of a UTC date and time.
private func at(_ text: String) -> Int64 {
    Int64(ISO8601DateFormatter().date(from: text)!.timeIntervalSince1970 * 1000)
}

@Test func payloadsCarryTheSessionCrons() throws {
    let p = try payload("Stop-session-crons")
    #expect(p.sessionCrons == [.init(schedule: "31 14 * * *", recurring: false)])
    #expect(try payload("Stop").sessionCrons == [])
    let unflagged = HookPayload.parse(Data(#"{"session_crons":[{"schedule":"1 2 * * *"},{"recurring":false},7]}"#.utf8))
    #expect(unflagged?.sessionCrons == [.init(schedule: "1 2 * * *", recurring: true)], "unflagged counts as recurring")
}

@Test func aStopRecordsTheRunningShellsWhenFirstSeen() throws {
    let stop = try payload("Stop-background-tasks")
    let first = apply(stop, to: nil, at: 1000)
    #expect(shells(first) == ["bk3m9qx2p": 1000], "the subagent isn't a shell")
    let again = apply(stop, to: first, at: 2000)
    #expect(shells(again) == ["bk3m9qx2p": 1000], "keeps the first-seen time")
}

@Test func aShellMissingFromTheNextStopIsRemoved() throws {
    let running = apply(try payload("Stop-background-tasks"), to: nil, at: 1000)
    let stopped = apply(try payload("Stop"), to: running, at: 2000)
    #expect(stopped?["backgroundShells"] == nil)
}

@Test func aFinishedShellDoesNotCount() throws {
    var stop = try payload("Stop")
    stop.backgroundTasks = [.init(id: "b1", type: "shell", status: "completed"), .init(id: "", type: "shell")]
    #expect(apply(stop, to: nil, at: 1000)?["backgroundShells"] == nil)
}

@Test func aStopWithoutTheListsKeepsTheRecordedWork() throws {
    var bare = try payload("Stop")
    bare.backgroundTasks = nil
    bare.sessionCrons = nil
    let s = apply(bare, to: ["backgroundShells": ["b1": 5], "wakeupAt": 9000], at: 1000)
    #expect(shells(s) == ["b1": 5] && wakeup(s) == 9000)
}

@Test func aSubagentStopRecordsTheParentsAndItsOwnShells() throws {
    let s = apply(try payload("SubagentStop-background-tasks"), to: ["state": "busy"], at: 1000)
    #expect(shells(s) == ["bk3m9qx2p": 1000, "bt5n2wz8r": 1000])
}

@Test func anOlderSubagentStopRecordsNothing() throws {
    let s = apply(try payload("SubagentStop-background-tasks"), to: ["state": "busy", "eventAt": 5000], at: 6000, started: 1000)
    #expect(s?["backgroundShells"] == nil)
}

@Test func aStopRecordsWhenTheWakeupIsDue() throws {
    let s = apply(try payload("Stop-session-crons"), to: nil, at: at("2026-11-13T14:21:05Z"))
    #expect(wakeup(s) == at("2026-11-13T14:31:00Z"))
    let fired = apply(try payload("Stop"), to: s, at: at("2026-11-13T14:32:00Z"))
    #expect(fired?["wakeupAt"] == nil, "no cron left")
}

@Test func withoutATimeZoneTheHooksOwnIsUsed() throws {
    let now = at("2026-11-13T14:21:05Z")
    guard case .write(let s) = HookEvents.apply(
        try payload("Stop-session-crons"), to: nil, now: now, started: now, storePromptPreview: true)
    else { Issue.record("no write"); return }
    let due = try #require(wakeup(s))
    #expect(due > now - 60_000 && due <= now + 86_400_000, "due within a day, in whatever zone this machine is in")
}

@Test func recurringCronsAreNotWakeups() throws {
    var stop = try payload("Stop")
    stop.sessionCrons = [.init(schedule: "*/5 * * * *", recurring: true), .init(schedule: "40 14 * * *", recurring: true)]
    #expect(apply(stop, to: nil, at: 1000)?["wakeupAt"] == nil)
}

@Test func theEarliestWakeupCounts() throws {
    var stop = try payload("Stop")
    stop.sessionCrons = [.init(schedule: "50 14 * * *", recurring: false), .init(schedule: "40 14 * * *", recurring: false)]
    #expect(wakeup(apply(stop, to: nil, at: at("2026-11-13T14:30:00Z"))) == at("2026-11-13T14:40:00Z"))
}

@Test func aNewSessionDropsTheBackgroundWork() throws {
    let old: [String: Any] = ["state": "idle", "backgroundShells": ["b1": 5], "wakeupAt": 9000]
    let fresh = apply(try payload("SessionStart"), to: old, at: 1000)
    #expect(fresh?["backgroundShells"] == nil && fresh?["wakeupAt"] == nil)
    var compact = try payload("SessionStart")
    compact.source = "compact"
    let kept = apply(compact, to: old, at: 1000)
    #expect(shells(kept) == ["b1": 5] && wakeup(kept) == 9000)
}

@Test func aWakeupIsDueTodayOrTomorrow() {
    #expect(HookEvents.dueTime("31 14 * * *", after: at("2026-11-13T14:30:30Z"), in: utc) == at("2026-11-13T14:31:00Z"))
    #expect(HookEvents.dueTime("31 14 * * *", after: at("2026-11-13T14:31:20Z"), in: utc) == at("2026-11-13T14:31:00Z"),
            "the minute under way hasn't passed")
    #expect(HookEvents.dueTime("31 14 * * *", after: at("2026-11-13T14:32:00Z"), in: utc) == at("2026-11-14T14:31:00Z"))
    #expect(HookEvents.dueTime("5 0 * * *", after: at("2026-11-13T23:50:00Z"), in: utc) == at("2026-11-14T00:05:00Z"),
            "across midnight")
}

@Test func aWakeupIsDueInTheGivenTimeZone() {
    let istanbul = TimeZone(identifier: "Europe/Istanbul")!  // UTC+3
    #expect(HookEvents.dueTime("11 20 * * *", after: at("2026-11-13T17:09:58Z"), in: istanbul) == at("2026-11-13T17:11:00Z"))
}

@Test func otherCronLinesHaveNoDueTime() {
    for line in ["*/5 * * * *", "31 14 13 11 *", "60 1 * * *", "1 24 * * *", "31 14", ""] {
        #expect(HookEvents.dueTime(line, after: 0, in: utc) == nil, "\(line)")
    }
}
