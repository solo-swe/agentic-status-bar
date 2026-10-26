import Foundation
import Testing
@testable import ASBCore

private func raw(_ json: String, _ path: String = "state/s1.json") -> RawFile {
    RawFile(path: path, contents: Data(json.utf8))
}

@Test func parsesEveryField() throws {
    let file = raw("""
        {"v":1,"sessionId":"s1","state":"waiting","reason":"permission","message":"m","updatedAt":2000,
         "stateSince":1500,"pid":4242,"procStart":"Mon Oct 19 09:12:03 2026","cwd":"/x/p","kind":"headless",
         "termBundleId":"com.example.term","herdrPane":"w2:p1","transcriptPath":"/t.jsonl","lastTool":"Bash",
         "promptPreview":"hi","promptAt":1400,"subagents":{"a1":{"type":"Explore","since":1600}},"future":true}
        """)
    let s = try #require(StateFile.parse(file))
    #expect(s.sessionId == "s1" && s.state == "waiting" && s.reason == "permission" && s.message == "m")
    #expect(s.updatedAt == 2000 && s.stateSince == 1500 && s.promptAt == 1400)
    #expect(s.pid == 4242 && s.procStart == "Mon Oct 19 09:12:03 2026")
    #expect(s.cwd == "/x/p" && s.kind == "headless" && s.termBundleId == "com.example.term")
    #expect(s.herdrPane == "w2:p1" && s.transcriptPath == "/t.jsonl" && s.lastTool == "Bash")
    #expect(s.promptPreview == "hi")
    #expect(s.subagents == ["a1": .init(type: "Explore", since: 1600)])
}

@Test func onlyVersionIsRequired() throws {
    let s = try #require(StateFile.parse(raw(#"{"v":1}"#, "/dir/abc-123.json")))
    #expect(s.sessionId == "abc-123")
    #expect(s.state == nil && s.pid == nil && s.subagents.isEmpty)
}

@Test func wrongTypesCountAsAbsent() throws {
    let s = try #require(StateFile.parse(raw(#"{"v":1,"sessionId":"s1","pid":"4242","updatedAt":true,"state":3}"#)))
    #expect(s.pid == nil && s.updatedAt == nil && s.state == nil)
}

@Test func nullPidMeansNone() throws {
    let s = try #require(StateFile.parse(raw(#"{"v":1,"sessionId":"s1","pid":null}"#)))
    #expect(s.pid == nil)
}

@Test(arguments: ["not json", "[1,2]", #"{"state":"busy"}"#, #"{"v":2,"state":"busy"}"#, #"{"v":0}"#,
                  #"{"v":"1"}"#, #"{"v":true}"#, ""])
func invalidFiles(_ json: String) {
    #expect(StateFile.parse(raw(json)) == nil)
}

@Test func countsInvalidFilesAndKeepsValidOnes() {
    let parsed = ParsedStates.parse([
        raw(#"{"v":1,"sessionId":"a","state":"busy"}"#, "state/a.json"),
        raw(#"{"v":1,"sessionId":"b","state":"busy"}"#, "state/b.json"),
        raw("not json", "state/corrupt.json"),
        raw(#"{"v":2,"state":"busy"}"#, "state/future.json"),
        raw("[1,2]", "state/array.json"),
    ])
    #expect(parsed.sessions.map(\.sessionId) == ["a", "b"])
    #expect(parsed.invalidCount == 3)
}

@Test func readsOnlyJsonFilesFromTheStateDir() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("asb-state-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(#"{"v":1,"sessionId":"a"}"#.utf8).write(to: dir.appendingPathComponent("a.json"))
    try Data("partial".utf8).write(to: dir.appendingPathComponent("a.json.tmp.123"))
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("a.json.lock"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: dir.appendingPathComponent("mutes"))
    try Data("x".utf8).write(to: dir.appendingPathComponent("plugin.log"))

    let files = StateDirectory.read(dir.path)
    #expect(files.map { ($0.path as NSString).lastPathComponent } == ["a.json"])
    #expect(StateDirectory.read(dir.appendingPathComponent("missing").path).isEmpty)
}
