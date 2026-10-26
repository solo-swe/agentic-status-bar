import Foundation
import Testing
@testable import ASBCore

private let la = TimeZone(identifier: "America/Los_Angeles")!
/// "Mon Oct 19 09:12:03 2026" in Los Angeles.
private let claudeStart: Int64 = 1_792_426_323

/// The hook (pid 5001) runs under a shell (5000) under claude (4242).
private let tree = FakeProcessInspector([
    ProcessRecord(pid: 5001, ppid: 5000, start: claudeStart + 60, comm: "asb", args: "asb hook"),
    ProcessRecord(pid: 5000, ppid: 4242, start: claudeStart + 60, comm: "/bin/sh", args: "sh -c asb hook"),
    ProcessRecord(pid: 4242, ppid: 1, start: claudeStart, comm: "claude", args: "claude --resume"),
])

@Test func gatherFindsTheClaudeProcessAndItsStart() {
    let m = HookMetadata.gather(environment: ["CLAUDE_CODE_ENTRYPOINT": "cli"], parentPid: 5000, inspector: tree, timeZone: la)
    #expect(m.pid == 4242)
    #expect(m.procStart == "Mon Oct 19 09:12:03 2026")
    #expect(m.kind == "interactive")
    #expect(m.herdrPane == nil && m.termBundleId == nil)
}

@Test func theWalkCanStartFromTheTestOverride() {
    let m = HookMetadata.gather(environment: ["ASB_PARENT_PID": "5001"], parentPid: 1, inspector: tree, timeZone: la)
    #expect(m.pid == 4242)
}

@Test func claudeRunningUnderNodeIsFound() {
    let npm = FakeProcessInspector([
        ProcessRecord(pid: 5000, ppid: 4300, start: 1, comm: "sh"),
        ProcessRecord(pid: 4300, ppid: 1, start: 2, comm: "/usr/local/bin/node", args: "node /usr/local/bin/claude"),
    ])
    #expect(HookMetadata.findClaude(from: 5000, inspector: npm) == 4300)
    let otherNode = FakeProcessInspector([ProcessRecord(pid: 4300, ppid: 1, start: 2, comm: "node", args: "node server.js")])
    #expect(HookMetadata.findClaude(from: 4300, inspector: otherNode) == nil)
}

@Test func withoutAClaudeAncestorThePidIsNil() {
    let shells = FakeProcessInspector((2...20).map { ProcessRecord(pid: Int32($0), ppid: Int32($0 - 1), start: 1, comm: "sh") })
    #expect(HookMetadata.findClaude(from: 20, inspector: shells) == nil)
    let m = HookMetadata.gather(environment: [:], parentPid: 20, inspector: shells)
    #expect(m.pid == nil && m.procStart == nil)
}

@Test func theWalkLooksAtSixProcesses() {
    // Like the shell hook: the start and five ancestors.
    var records = [ProcessRecord(pid: 100, ppid: 1, start: 1, comm: "claude")]
    for pid in 101...107 { records.append(ProcessRecord(pid: Int32(pid), ppid: Int32(pid - 1), start: 1, comm: "sh")) }
    #expect(HookMetadata.findClaude(from: 105, inspector: FakeProcessInspector(records)) == 100)
    #expect(HookMetadata.findClaude(from: 106, inspector: FakeProcessInspector(records)) == nil)
}

@Test func kindComesFromTheEntrypointAndThePrintFlag() {
    #expect(HookMetadata.kind(entrypoint: "sdk-cli", arguments: nil) == "headless")
    #expect(HookMetadata.kind(entrypoint: "claude-vscode", arguments: nil) == "ide")
    #expect(HookMetadata.kind(entrypoint: "jetbrains", arguments: nil) == "ide")
    #expect(HookMetadata.kind(entrypoint: "claude-desktop", arguments: nil) == "desktop")
    #expect(HookMetadata.kind(entrypoint: "cli", arguments: "claude -p hello") == "headless")
    #expect(HookMetadata.kind(entrypoint: "cli", arguments: "claude --print hello") == "headless")
    #expect(HookMetadata.kind(entrypoint: "cli", arguments: "claude --resume") == "interactive")
    #expect(HookMetadata.kind(entrypoint: "", arguments: nil) == "interactive")
}

@Test func herdrPaneAndBundleIdComeFromTheEnvironment() {
    let m = HookMetadata.gather(environment: ["HERDR_PANE_ID": "w2:p1", "__CFBundleIdentifier": "com.mitchellh.ghostty"],
                                parentPid: 5000, inspector: tree)
    #expect(m.herdrPane == "w2:p1" && m.termBundleId == "com.mitchellh.ghostty")
    let empty = HookMetadata.gather(environment: ["HERDR_PANE_ID": "", "__CFBundleIdentifier": ""], parentPid: 5000, inspector: tree)
    #expect(empty.herdrPane == nil && empty.termBundleId == nil)
}

@Test func applyRecordsTheDetailsAndDropsWhatIsUnknown() {
    var state: [String: Any] = ["herdrPane": "old", "termBundleId": "old", "procStart": "old", "state": "busy"]
    HookMetadata(pid: nil, procStart: nil, kind: "headless", herdrPane: nil, termBundleId: nil)
        .apply(to: &state, cwd: "/x/p", transcriptPath: "/t.jsonl")
    #expect(state["pid"] is NSNull && state["procStart"] == nil)
    #expect(state["herdrPane"] == nil && state["termBundleId"] == nil)
    #expect(state["cwd"] as? String == "/x/p" && state["transcriptPath"] as? String == "/t.jsonl" && state["kind"] as? String == "headless")
    #expect(state["state"] as? String == "busy")

    HookMetadata(pid: 4242, procStart: "Mon Oct 19 09:12:03 2026", kind: "interactive", herdrPane: "w2:p1", termBundleId: "b")
        .apply(to: &state, cwd: "/x/p", transcriptPath: "/t.jsonl")
    #expect(state["pid"] as? Int == 4242 && state["procStart"] as? String == "Mon Oct 19 09:12:03 2026")
    #expect(state["herdrPane"] as? String == "w2:p1" && state["termBundleId"] as? String == "b")
}

@Test func sessionStartRecordsTheDetailsThenGoesIdle() throws {
    var p = HookPayload()
    p.event = "SessionStart"
    p.sessionId = "s1"
    p.cwd = "/x/p"
    p.transcriptPath = "/t.jsonl"
    let m = HookMetadata(pid: 4242, procStart: "Mon Oct 19 09:12:03 2026", kind: "interactive", herdrPane: nil, termBundleId: nil)
    guard case .write(let s) = HookEvents.apply(p, to: ["state": "busy", "reason": "x"], now: 1000, started: 1000,
                                                storePromptPreview: true,
                                                sessionStartChanges: { m.apply(to: &$0, cwd: p.cwd, transcriptPath: p.transcriptPath) })
    else { Issue.record("expected a write"); return }
    #expect(s["state"] == AnyHashable("idle") && s["reason"] == nil)
    #expect(s["pid"] == AnyHashable(4242) && s["cwd"] == AnyHashable("/x/p"))
}

@Test func backfillIsNeededOnlyWithoutPidOrCwd() {
    #expect(HookMetadata.needsBackfill(["state": "busy"]))
    #expect(HookMetadata.needsBackfill(["pid": 1]))
    #expect(!HookMetadata.needsBackfill(["pid": 1, "cwd": "/x"]))
    // pid null means "looked, none found": don't look again.
    #expect(!HookMetadata.needsBackfill(["pid": NSNull(), "cwd": "/x"]))
}

@Test func staleFilesAreOtherSessionsOfTheSameProcess() {
    let files = [
        RawFile(path: "state/new.json", contents: Data(#"{"v":1,"sessionId":"new","pid":4242}"#.utf8)),
        RawFile(path: "state/old.json", contents: Data(#"{"v":1,"sessionId":"old","pid":4242}"#.utf8)),
        RawFile(path: "state/other.json", contents: Data(#"{"v":1,"sessionId":"other","pid":7}"#.utf8)),
    ]
    #expect(HookMetadata.staleFiles(for: 4242, in: files, own: "state/new.json") == ["state/old.json"])
}
