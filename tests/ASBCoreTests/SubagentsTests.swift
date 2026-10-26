import Foundation
import Testing
@testable import ASBCore

private let now: Int64 = 1_792_891_080_000

/// The checks on one session (no pid) with `state`; C5 off unless `config` turns it on.
private func checked(_ state: String, config: String = "stale_minutes=0", transcript: Data? = nil) -> ReconciledSession {
    var inputs = SnapshotInputs(now: now, timeZone: .gmt, configText: config)
    inputs.stateFiles = [RawFile(path: "state/s1.json", contents: Data(#"{"v":1,"sessionId":"s1",\#(state)}"#.utf8))]
    if let transcript { inputs.transcripts = ["t.jsonl": TranscriptInput(mtime: 0, contents: transcript)] }
    return Engine.reconcile(inputs).sessions[0]
}

private let twoAgents = #""subagents":{"a1":{"type":"Explore","since":\#(now - 90_000)},"a2":{"type":"Plan","since":\#(now - 30_000)}}"#
private let oneAgent = #""subagents":{"a1":{"type":"Explore","since":\#(now - 5_000)}}"#

@Test func anIdleParentWithRunningSubagentsWaitsOnThem() {
    let s = checked(#""state":"idle","updatedAt":\#(now),\#(twoAgents)"#)
    #expect(s.shown == "subagents")
    #expect(s.shownSince == now - 90_000)
}

@Test func aParentBlockedInItsTaskOrAgentToolWaitsOnItsSubagent() {
    #expect(checked(#""state":"busy","updatedAt":\#(now),"lastTool":"Agent",\#(oneAgent)"#).shown == "subagents")
    #expect(checked(#""state":"busy","updatedAt":\#(now),"lastTool":"Task",\#(oneAgent)"#).shown == "subagents")
}

@Test func aParentWorkingWithItsOwnToolsWhileSubagentsRunStaysBusy() {
    #expect(checked(#""state":"busy","updatedAt":\#(now),"lastTool":"Bash",\#(oneAgent)"#).shown == "busy")
}

@Test func aParentWaitingOnTheUserStaysWaitingWhileSubagentsRun() {
    #expect(checked(#""state":"waiting","reason":"permission","updatedAt":\#(now),\#(oneAgent)"#).shown == "waiting")
}

@Test func anInterruptWinsOverLeftoverSubagents() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/transcripts/denied-permission.jsonl")
    let s = checked(#""state":"busy","updatedAt":\#(now),"lastTool":"Agent","transcriptPath":"t.jsonl",\#(oneAgent)"#,
                    transcript: try Data(contentsOf: fixture))
    #expect(s.shown == "idle")
}

@Test func aParentWaitingOnSubagentsWithNoActivityPastTheThresholdIsUncertain() {
    let old = now - 45 * 60_000
    let s = checked(#""state":"idle","updatedAt":\#(old),"subagents":{"a1":{"type":"Explore","since":\#(old)}}"#,
                    config: "stale_minutes=30")
    #expect(s.shown == "uncertain")
}

@Test func withoutSubagentsNothingChanges() {
    #expect(checked(#""state":"idle","updatedAt":\#(now)"#).shown == "idle")
}

// MARK: Filters

private func kinds(_ config: String) -> [String] {
    var inputs = SnapshotInputs(now: now, timeZone: .gmt, configText: config + "\nstale_minutes=0")
    inputs.stateFiles = [
        (#"{"v":1,"sessionId":"cli","state":"busy","kind":"interactive"}"#, "cli"),
        (#"{"v":1,"sessionId":"script","state":"waiting","kind":"headless"}"#, "script"),
        (#"{"v":1,"sessionId":"vscode","state":"idle","kind":"ide"}"#, "vscode"),
        (#"{"v":1,"sessionId":"app","state":"idle","kind":"desktop"}"#, "app"),
        (#"{"v":1,"sessionId":"old","state":"busy"}"#, "old"),
    ].map { RawFile(path: "state/\($0.1).json", contents: Data($0.0.utf8)) }
    let config = Config.parse(inputs.configText)
    return Filters.apply(Engine.reconcile(inputs).sessions, config).map(\.file.sessionId)
}

@Test func hiddenKindsAreLeftOut() {
    #expect(kinds("show_headless=0\nshow_ide=0") == ["cli", "old"])
    #expect(kinds("show_interactive=0") == ["script", "vscode", "app"])
}

@Test func sessionsWithoutAKindCountAsInteractive() {
    #expect(kinds("").contains("old"))
    #expect(!kinds("show_interactive=0").contains("old"))
}

@Test func showSubagentsDoesNotHideSessions() {
    #expect(kinds("show_subagents=0").count == 5)
}

@Test func unknownKindsAreAlwaysShown() {
    #expect(Filters.shows(kind: "something-new", Config.parse("show_interactive=0\nshow_headless=0\nshow_ide=0")))
}
