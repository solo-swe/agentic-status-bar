import Foundation
import Testing
@testable import ASBCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/transcripts")

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtures.appendingPathComponent("\(name).jsonl"))
}

private func line(_ json: String) -> Data { Data((json + "\n").utf8) }

/// Runs C3 on one session whose state file says `state` and whose transcript is `transcript`.
private func afterC3(state: String, extra: String = "", transcript: Data?) -> ReconciledSession {
    let json = #"{"v":1,"sessionId":"s1","state":"\#(state)","updatedAt":5000,"transcriptPath":"t.jsonl"\#(extra)}"#
    let session = ReconciledSession(StateFile.parse(RawFile(path: "state/s1.json", contents: Data(json.utf8)))!)
    let transcripts = transcript.map { ["t.jsonl": TranscriptInput(mtime: 0, contents: $0)] } ?? [:]
    return Checks.interrupts([session], transcripts: transcripts)[0]
}

@Test func c3ShowsABusySessionAsIdleAfterADeniedPermission() throws {
    let s = afterC3(state: "busy", transcript: try fixture("denied-permission"))
    #expect(s.shown == "idle" && s.shownSince == 5000 && s.interrupted)
}

@Test func c3ShowsAWaitingSessionAsIdleAfterADeniedPermission() throws {
    #expect(afterC3(state: "waiting", extra: #","reason":"permission""#, transcript: try fixture("denied-permission")).shown == "idle")
}

@Test func c3ShowsABusySessionAsIdleWhenTheTurnAlreadyEnded() throws {
    #expect(afterC3(state: "busy", transcript: try fixture("completed-turn")).shown == "idle")
}

@Test func c3LeavesASessionBusyWhenEscCameBeforeAnyOutput() throws {
    let s = afterC3(state: "busy", transcript: try fixture("esc-before-output"))
    #expect(s.shown == "busy" && !s.interrupted)
}

@Test func c3LeavesASessionBusyWhileItsTurnIsStillRunning() throws {
    var data = try fixture("denied-permission")
    data.append(line(#"{"type":"user","message":{"role":"user","content":"Try again with npm ci"}}"#))
    data.append(line(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#))
    #expect(afterC3(state: "busy", transcript: data).shown == "busy")
}

@Test func c3OnlyReadsTheLast8KB() throws {
    var data = try fixture("denied-permission")
    let filler = String(repeating: "x", count: 500)
    for _ in 0..<30 {
        data.append(line(#"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(filler)"}]}}"#))
    }
    #expect(data.count > Transcript.tailBytes)
    #expect(!Transcript.tailEntries(data).isEmpty)
    #expect(afterC3(state: "busy", transcript: data).shown == "busy")
}

@Test func c3IgnoresIdleSessionsAndMissingTranscripts() throws {
    #expect(afterC3(state: "idle", transcript: try fixture("denied-permission")).interrupted == false)
    #expect(afterC3(state: "busy", transcript: nil).shown == "busy")
}

@Test func c3OnlyReadsTranscriptsOfFilesThatSayBusyOrWaiting() throws {
    // The registry made an idle file look busy: its transcript isn't read, as in the shell plugin.
    let json = #"{"v":1,"sessionId":"s1","state":"idle","updatedAt":5000,"transcriptPath":"t.jsonl"}"#
    var session = ReconciledSession(StateFile.parse(RawFile(path: "s", contents: Data(json.utf8)))!)
    session.shown = "busy"
    let result = Checks.interrupts([session], transcripts: ["t.jsonl": TranscriptInput(mtime: 0, contents: try fixture("completed-turn"))])
    #expect(result[0].shown == "busy")
}

@Test func tailDropsTheCutFirstLineAndSkipsNonJson() {
    // A long first line that the 8 KB tail cuts in the middle.
    var data = line(String(repeating: "y", count: Transcript.tailBytes))
    data.append(line(#"{"type":"system","subtype":"turn_duration"}"#))
    data.append(line("not json"))
    let entries = Transcript.tailEntries(data)
    #expect(entries.count == 1)
    #expect(entries.first?["subtype"] as? String == "turn_duration")
}

@Test func metaAndToolResultEntriesAreNotPrompts() {
    #expect(!Transcript.isPrompt(["type": "user", "isMeta": true, "message": ["content": "x"]]))
    #expect(!Transcript.isPrompt(["type": "user", "message": ["content": [["type": "tool_result"]]]]))
    #expect(Transcript.isPrompt(["type": "user", "message": ["content": [["type": "text", "text": "hi"]]]]))
}
