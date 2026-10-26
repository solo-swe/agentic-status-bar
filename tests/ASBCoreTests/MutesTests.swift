import Foundation
import Testing
@testable import ASBCore

private let la = TimeZone(identifier: "America/Los_Angeles")!
/// Sat Oct 24 2026, 18:18:00 in Los Angeles.
private let now: Int64 = 1_792_891_080_000

private func session(_ id: String, _ fields: String) -> ReconciledSession {
    ReconciledSession(StateFile.parse(RawFile(path: "state/\(id).json", contents: Data(#"{"v":1,"sessionId":"\#(id)",\#(fields)}"#.utf8)))!)
}

private func tempMutesFile() -> String {
    FileManager.default.temporaryDirectory.appendingPathComponent("asb-mutes-\(UUID().uuidString)/mutes").path
}

@Test func muteHourLastsSixtyMinutes() {
    var mutes: [String: Mute] = [:]
    Mutes.muteHour(&mutes, cwd: "/x/alpha", now: now)
    #expect(mutes["/x/alpha"] == Mute(until: now + 3_600_000, at: now, today: false))
}

@Test func muteTodayLastsUntilLocalMidnight() {
    var mutes: [String: Mute] = [:]
    Mutes.muteToday(&mutes, cwd: "/x/alpha", now: now, timeZone: la)
    let until = mutes["/x/alpha"]!.until
    // Sunday Oct 25 2026, 00:00 in Los Angeles: 5 h 42 min later.
    #expect(until == now + (5 * 60 + 42) * 60_000)
    #expect(mutes["/x/alpha"]!.today)
}

@Test func midnightAcrossAMonthEnd() {
    let utc = TimeZone(identifier: "UTC")!
    // 2026-10-31 23:30 UTC → 2026-11-01 00:00 UTC.
    let lateOctober: Int64 = 1_793_489_400_000
    #expect(Mutes.nextMidnight(after: lateOctober, timeZone: utc) == 1_793_491_200_000)
}

@Test func activeMutesIgnoreExpiredOnes() {
    let mutes = ["/x/alpha": Mute(until: 1000, at: 500, today: false), "/x/beta": Mute(until: now + 1, at: now - 1, today: false)]
    #expect(Array(Mutes.active(mutes, sessions: [], now: now).keys) == ["/x/beta"])
}

@Test func aPromptSentAfterTheMuteLiftsIt() {
    let mutes = ["/x/alpha": Mute(until: now + 3_600_000, at: now - 10_000, today: false)]
    let prompted = session("a", #""state":"idle","cwd":"/x/alpha","promptAt":\#(now - 5_000)"#)
    #expect(Mutes.active(mutes, sessions: [prompted], now: now).isEmpty)
    let before = session("a", #""state":"idle","cwd":"/x/alpha","promptAt":\#(now - 60_000)"#)
    #expect(Mutes.active(mutes, sessions: [before], now: now).count == 1)
}

@Test func aPromptInAnyOfTheProjectsSessionsCounts() {
    let mutes = ["/x/alpha": Mute(until: now + 3_600_000, at: now - 10_000, today: false)]
    let quiet = session("a", #""state":"idle","cwd":"/x/alpha""#)
    let prompted = session("b", #""state":"busy","cwd":"/x/alpha","promptAt":\#(now - 1_000)"#)
    #expect(Mutes.active(mutes, sessions: [quiet, prompted], now: now).isEmpty)
}

@Test func everySessionInAMutedProjectIsMutedButWaitingBreaksThrough() {
    let active = ["/x/alpha": Mute(until: now + 3_600_000, at: now, today: true)]
    let marked = Mutes.apply([
        session("a", #""state":"idle","cwd":"/x/alpha""#),
        session("b", #""state":"busy","cwd":"/x/alpha""#),
        session("c", #""state":"waiting","reason":"permission","cwd":"/x/alpha""#),
        session("d", #""state":"idle","cwd":"/x/beta""#),
    ], active: active)
    #expect(marked.map(\.muted) == [true, true, false, false])
    #expect(marked[2].muteUntil == now + 3_600_000 && marked[2].muteToday)
    #expect(marked[3].muteUntil == nil)
}

@Test func corruptOrOddMutesFilesCountAsNoMutes() {
    #expect(Mutes.parse("garbage").isEmpty)
    #expect(Mutes.parse("[1]").isEmpty)
    #expect(Mutes.parse(nil).isEmpty)
    #expect(Mutes.parse(#"{"/x/a":{"at":1},"/x/b":{"until":5,"at":1,"today":true}}"#) == ["/x/b": Mute(until: 5, at: 1, today: true)])
}

@Test func updateWritesSortedJsonAndDropsExpiredMutes() throws {
    let file = tempMutesFile()
    try Mutes.update(file: file, now: now) { Mutes.muteHour(&$0, cwd: "/x/beta", now: now) }
    try FileManager.default.removeItem(atPath: file)
    try #"{"/x/old":{"until":1000,"at":500,"today":false}}"#.write(toFile: file, atomically: true, encoding: .utf8)
    try Mutes.update(file: file, now: now) { Mutes.muteHour(&$0, cwd: "/x/alpha", now: now) }
    let text = try String(contentsOfFile: file, encoding: .utf8)
    #expect(text == #"{"/x/alpha":{"at":1792891080000,"today":false,"until":1792894680000}}"#)
}

@Test func unmuteAndUnmuteAll() throws {
    let file = tempMutesFile()
    try Mutes.update(file: file, now: now) {
        Mutes.muteHour(&$0, cwd: "/x/alpha", now: now)
        Mutes.muteToday(&$0, cwd: "/x/beta", now: now, timeZone: la)
    }
    try Mutes.update(file: file, now: now) { $0["/x/alpha"] = nil }
    #expect(Array(Mutes.parse(try String(contentsOfFile: file, encoding: .utf8)).keys) == ["/x/beta"])
    try Mutes.update(file: file, now: now) { $0 = [:] }
    #expect(try String(contentsOfFile: file, encoding: .utf8) == "{}")
}

@Test func aCorruptFileIsReplacedOnTheNextChange() throws {
    let file = tempMutesFile()
    try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try "garbage".write(toFile: file, atomically: true, encoding: .utf8)
    try Mutes.update(file: file, now: now) { Mutes.muteHour(&$0, cwd: "/x/alpha", now: now) }
    #expect(Array(Mutes.parse(try String(contentsOfFile: file, encoding: .utf8)).keys) == ["/x/alpha"])
}
