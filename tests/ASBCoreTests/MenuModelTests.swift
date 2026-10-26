import Foundation
import Testing
@testable import ASBCore

private let la = TimeZone(identifier: "America/Los_Angeles")!
private let now: Int64 = 1_792_891_080_000
private func ago(_ seconds: Int64) -> Int64 { now - seconds * 1000 }

/// A snapshot of sessions given as (id, fields) without pids; C5 off unless the config says otherwise.
private func snapshot(_ sessions: [(String, String)], config: String = "", herdr: String? = nil, mutes: String? = nil) -> Snapshot {
    var inputs = SnapshotInputs(now: now, timeZone: la, configText: "stale_minutes=0\n" + config, mutesText: mutes)
    inputs.stateFiles = sessions.map { id, fields in
        let updated = fields.contains(#""updatedAt""#) ? "" : #""updatedAt":\#(now),"#
        return RawFile(path: "state/\(id).json", contents: Data(#"{"v":1,"sessionId":"\#(id)",\#(updated)\#(fields)}"#.utf8))
    }
    if let herdr {
        inputs.herdrList = herdr
        inputs.herdrInstalled = true
    }
    return Engine.snapshot(inputs).snapshot
}

// MARK: Header

@Test func noSessionsShowsTheFaintIconWithoutANumber() {
    let h = snapshot([]).header
    #expect(h.state == .none && h.symbol == "sparkle" && h.color == "#C7C7CC,#48484A" && h.count == nil)
}

@Test func waitingWinsAndCountsWaitingSessions() {
    let h = snapshot([
        ("a", #""state":"waiting","reason":"permission""#), ("b", #""state":"waiting","reason":"question""#),
        ("c", #""state":"idle""#), ("d", #""state":"busy""#),
    ]).header
    #expect(h.state == .waiting && h.count == 2 && h.symbol == "exclamationmark.circle.fill" && h.color == "#D70015,#FF453A")
}

@Test func idleWinsOverBusy() {
    let h = snapshot([("a", #""state":"idle""#), ("b", #""state":"busy""#), ("c", #""state":"busy""#)]).header
    #expect(h.state == .idle && h.count == 1 && h.symbol == "zzz" && h.color == "#B25000,#FFD60A")
}

@Test func allBusyShowsTheDimmedIconWithTheTotal() {
    let h = snapshot([("a", #""state":"busy""#), ("b", #""state":"busy""#), ("c", #""state":"busy""#)]).header
    #expect(h.state == .busy && h.count == 3 && h.symbol == "sparkle" && h.color == "#6E6E73,#AEAEB2")
}

@Test func theConfiguredIconIsUsedForBusyAndEmpty() {
    #expect(snapshot([("a", #""state":"busy""#)], config: "icon=bolt").header.symbol == "bolt")
    #expect(snapshot([], config: "icon=bolt").header.symbol == "bolt")
}

@Test func invalidFilesShowTheWarningWithAllSessions() {
    var inputs = SnapshotInputs(now: now, timeZone: la, configText: "stale_minutes=0")
    inputs.stateFiles = [
        RawFile(path: "state/ok.json", contents: Data(#"{"v":1,"sessionId":"ok","state":"busy"}"#.utf8)),
        RawFile(path: "state/bad.json", contents: Data("not json".utf8)),
    ]
    let s = Engine.snapshot(inputs).snapshot
    #expect(s.header.state == .warning && s.header.count == 1 && s.header.symbol == "exclamationmark.triangle")
    #expect(s.invalidFiles == 1)
}

@Test func uncertainRanksBelowIdleAndAboveBusy() {
    let old = now - 45 * 60_000
    let config = "stale_minutes=30"
    #expect(snapshot([("a", #""state":"busy","updatedAt":\#(old)"#), ("b", #""state":"busy""#)], config: config).header.state == .uncertain)
    #expect(snapshot([("a", #""state":"busy","updatedAt":\#(old)"#), ("c", #""state":"idle""#)], config: config).header.state == .idle)
}

// MARK: Rows

@Test func rowsAreSortedByStateThenLongestInThatStateFirst() {
    let rows = snapshot([
        ("busy1", #""state":"busy","cwd":"/x/busy-old","stateSince":\#(ago(600))"#),
        ("idle1", #""state":"idle","cwd":"/x/idle-new","stateSince":\#(ago(30))"#),
        ("idle2", #""state":"idle","cwd":"/x/idle-old","stateSince":\#(ago(900))"#),
        ("wait1", #""state":"waiting","reason":"permission","cwd":"/x/waiter","stateSince":\#(ago(5))"#),
    ]).sessions
    #expect(rows.map(\.project) == ["waiter", "idle-old", "idle-new", "busy-old"])
}

@Test func aRowHasProjectTitleStateWordAndDuration() throws {
    let row = try #require(snapshot([("a", #""state":"waiting","reason":"permission","cwd":"/Users/alex/code/api-gateway","promptPreview":"Add rate limiting","stateSince":\#(ago(125))"#)]).sessions.first)
    #expect(row.label.hasPrefix("api-gateway — Add rate limiting "))
    #expect(row.word == "permission" && row.detail == "2m" && row.reason == "permission")
    #expect(row.symbol == "exclamationmark.circle.fill" && row.color == "#D70015,#FF453A")
}

@Test func stateWordsCoverQuestionIdleWorking() {
    let rows = snapshot([
        ("q", #""state":"waiting","reason":"question","cwd":"/x/q""#), ("i", #""state":"idle","cwd":"/x/i""#),
        ("b", #""state":"busy","cwd":"/x/b""#),
    ]).sessions
    #expect(rows.map(\.word) == ["question", "idle", "working"])
}

@Test func durationsUseSecondsMinutesHoursAndDays() {
    #expect(MenuModel.ago(ago(12), now: now) == "12s")
    #expect(MenuModel.ago(ago(300), now: now) == "5m")
    #expect(MenuModel.ago(ago(7300), now: now) == "2h")
    #expect(MenuModel.ago(ago(180_000), now: now) == "2d")
    #expect(MenuModel.ago(now + 5000, now: now) == "0s")
}

@Test func longLabelsAreCutWithAnEllipsisAndShortOnesPadded() {
    let long = MenuModel.label(project: "project", title: "A very long prompt preview that goes on and on past the limit")
    #expect(long.unicodeScalars.count == 48 && long.hasSuffix("…"))
    let short = MenuModel.label(project: "ab", title: "")
    #expect(short == "ab" + String(repeating: " ", count: 46))
    #expect(MenuModel.label(project: "abcdef", title: "x").unicodeScalars.count == 48)
}

@Test func aPipeInTheTitleDoesNotBreakSwiftBarParameters() {
    #expect(MenuModel.label(project: "p", title: "a | color=red").hasPrefix("p — a │ color=red"))
}

@Test func aNameBetweenColonsDoesNotBecomeASymbol() {
    #expect(MenuModel.label(project: "p", title: "fix the :bug: now").contains(":\u{200B}bug:"))
}

@Test func aSessionWithoutCwdOrTitleStillRenders() throws {
    let row = try #require(snapshot([("a", #""state":"idle""#)]).sessions.first)
    #expect(row.project == "unknown" && row.title == "" && row.label.hasPrefix("unknown "))
}

@Test func subagentRowsAreSortedAndHiddenWhenShowSubagentsIs0() throws {
    let fields = #""state":"busy","subagents":{"a1":{"type":"Explore","since":\#(ago(12))},"a2":{"type":"general-purpose","since":\#(ago(60))}}"#
    let row = try #require(snapshot([("s1", fields)]).sessions.first)
    #expect(row.subagents.map(\.type) == ["general-purpose", "Explore"])
    #expect(row.subagents.map(\.detail) == ["1m", "12s"])
    #expect(snapshot([("s1", fields)], config: "show_subagents=0").sessions.first?.subagents.isEmpty == true)
}

@Test func waitingOnSubagentsSaysHowMany() throws {
    let row = try #require(snapshot([("s1", #""state":"idle","subagents":{"a1":{"type":"Explore","since":\#(ago(90))},"a2":{"type":"Plan","since":\#(ago(30))}}"#)]).sessions.first)
    #expect(row.shown == .subagents && row.word == "waiting on 2 subagents" && row.detail == "1m" && row.symbol == "hourglass")
    let h = snapshot([("s1", #""state":"idle","subagents":{"a1":{"type":"Explore","since":\#(ago(5))}}"#)]).header
    #expect(h.state == .busy && h.count == 1)
}

// MARK: Titles and focus

private func herdr(_ agents: String) -> String {
    #"{"id":"cli:agent:list","result":{"agents":\#(agents),"type":"agent_list"}}"#
}

@Test func herdrTerminalTitlesArePreferredOverThePromptPreview() throws {
    let row = try #require(snapshot([("s1", #""state":"idle","promptPreview":"first prompt""#)],
        herdr: herdr(#"[{"agent":"claude","agent_session":{"value":"s1"},"terminal_title_stripped":"Spec for the parser","pane_id":"w2:p1"}]"#)).sessions.first)
    #expect(row.title == "Spec for the parser")
}

@Test func anEmptyOrUnreadableHerdrTitleFallsBack() throws {
    let empty = try #require(snapshot([("s1", #""state":"idle","promptPreview":"first prompt""#)],
        herdr: herdr(#"[{"agent":"claude","agent_session":{"value":"s1"},"terminal_title_stripped":""}]"#)).sessions.first)
    #expect(empty.title == "first prompt")
    let broken = try #require(snapshot([("s1", #""state":"idle","promptPreview":"first prompt""#)], herdr: "garbage").sessions.first)
    #expect(broken.title == "first prompt")
}

@Test func onlySessionsInAHerdrPaneAreFocusableAndOnlyWithHerdr() {
    let sessions = [("a", #""state":"idle","herdrPane":"w2:p1""#), ("b", #""state":"idle""#)]
    #expect(snapshot(sessions, herdr: herdr("[]")).sessions.map(\.focusable) == [true, false])
    #expect(snapshot(sessions).sessions.map(\.focusable) == [false, false])
}

// MARK: Mutes

@Test func mutedRowsComeLastWithTheMutedIconAndText() throws {
    let mutes = #"{"/x/alpha":{"until":\#(now + 3_600_000),"at":\#(now - 1000),"today":false}}"#
    let s = snapshot([("a", #""state":"idle","cwd":"/x/alpha""#), ("b", #""state":"busy","cwd":"/x/beta""#)], mutes: mutes)
    #expect(s.sessions.map(\.project) == ["beta", "alpha"])
    let muted = s.sessions[1]
    #expect(muted.muted && muted.symbol == "bell.slash" && muted.color == "#8E8E93,#98989D")
    #expect(muted.detail == "muted until 19:18" && muted.muteToday == false)
    #expect(s.header.state == .busy && s.header.count == 1 && s.activeMutes == 1)
}

@Test func allMutedShowsTheMutedIconWithoutANumber() {
    let mutes = #"{"/x/alpha":{"until":\#(now + 3_600_000),"at":\#(now - 1000),"today":true}}"#
    let s = snapshot([("a", #""state":"idle","cwd":"/x/alpha""#), ("b", #""state":"busy","cwd":"/x/alpha""#)], mutes: mutes)
    #expect(s.header.state == .muted && s.header.count == nil && s.header.symbol == "bell.slash")
    #expect(s.sessions.allSatisfy { $0.detail == "muted today" })
}

@Test func aMutedSessionWaitingOnTheUserStillAlerts() throws {
    let mutes = #"{"/x/alpha":{"until":\#(now + 3_600_000),"at":\#(now - 1000),"today":false}}"#
    let s = snapshot([("a", #""state":"waiting","reason":"permission","cwd":"/x/alpha","stateSince":\#(ago(5))"#)], mutes: mutes)
    #expect(s.header.state == .waiting)
    let row = try #require(s.sessions.first)
    #expect(!row.muted && row.muteUntil != nil && row.detail == "5s" && row.symbol == "exclamationmark.circle.fill")
}
