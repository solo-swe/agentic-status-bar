import Foundation
import Testing
@testable import ASBCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("asb-live-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func readTailKeepsOneExtraByteOfALongTranscript() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("t.jsonl").path
    var data = Data((String(repeating: "x", count: 20_000) + "\n").utf8)
    data.append(Data(#"{"type":"system","subtype":"turn_duration"}"#.utf8 + [10]))
    try data.write(to: URL(fileURLWithPath: path))

    let tail = try #require(LiveInputs.readTail(path))
    #expect(tail.contents.count == Transcript.tailBytes + 1)
    #expect(Transcript.tailEntries(tail.contents).count == 1)
    #expect(tail.mtime > 0)
    #expect(LiveInputs.readTail(dir.appendingPathComponent("missing").path) == nil)
}

@Test func gatherReadsStateConfigMutesAndOnlyBusyTranscripts() throws {
    let home = try tempDir()
    defer { try? FileManager.default.removeItem(at: home) }
    let state = home.appendingPathComponent("state")
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    let busyT = home.appendingPathComponent("busy.jsonl").path
    let idleT = home.appendingPathComponent("idle.jsonl").path
    try Data("{}\n".utf8).write(to: URL(fileURLWithPath: busyT))
    try Data("{}\n".utf8).write(to: URL(fileURLWithPath: idleT))
    try Data(#"{"v":1,"sessionId":"a","state":"busy","transcriptPath":"\#(busyT)"}"#.utf8).write(to: state.appendingPathComponent("a.json"))
    try Data(#"{"v":1,"sessionId":"b","state":"idle","transcriptPath":"\#(idleT)"}"#.utf8).write(to: state.appendingPathComponent("b.json"))
    try Data("{}".utf8).write(to: state.appendingPathComponent("mutes"))
    let config = home.appendingPathComponent("config").path
    try Data("use_registry=0\n".utf8).write(to: URL(fileURLWithPath: config))

    let env = ["ASB_STATE_DIR": state.path, "ASB_CONFIG": config,
               "ASB_HERDR": home.appendingPathComponent("no-herdr").path]
    let live = LiveInputs(paths: Paths.from(environment: env, home: home.path), environment: env,
                          inspector: FakeProcessInspector([ProcessRecord(pid: 7, ppid: 1, start: 1, comm: "x")]))
    let inputs = live.gather(now: 1000)
    #expect(inputs.stateFiles.count == 2)
    #expect(Array(inputs.transcripts.keys) == [busyT])
    #expect(inputs.configText == "use_registry=0\n")
    #expect(inputs.mutesText == "{}")
    #expect(inputs.processes.map(\.pid) == [7])
    #expect(!inputs.herdrInstalled && inputs.herdrList == nil)
}

@Test func applyDeletesOnlyDeadJsonFilesInsideTheStateDir() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let inside = dir.appendingPathComponent("dead.json").path
    let outside = FileManager.default.temporaryDirectory.appendingPathComponent("asb-outside-\(UUID().uuidString).json").path
    try Data("{}".utf8).write(to: URL(fileURLWithPath: inside))
    try Data("{}".utf8).write(to: URL(fileURLWithPath: outside))
    defer { try? FileManager.default.removeItem(atPath: outside) }

    let env = ["ASB_STATE_DIR": dir.path]
    let live = LiveInputs(paths: Paths.from(environment: env, home: dir.path), environment: env, inspector: FakeProcessInspector())
    let result = SnapshotResult(snapshot: Snapshot(generatedAt: 0, header: .init(state: .none, symbol: "", color: "")),
                                deadFiles: [inside, outside], registrySchemaIssue: true)
    live.apply(result, configText: nil)
    live.apply(result, configText: nil)
    #expect(!FileManager.default.fileExists(atPath: inside))
    #expect(FileManager.default.fileExists(atPath: outside))
    let log = try String(contentsOfFile: dir.appendingPathComponent("plugin.log").path, encoding: .utf8)
    #expect(log.split(separator: "\n").filter { $0.hasPrefix("[registry-schema] ") }.count == 1)
}

@Test func herdrIsOnlyTheOverrideWhenItIsSet() {
    #expect(Herdr.find(environment: ["ASB_HERDR": "/nonexistent/herdr"]) == nil)
    #expect(Herdr.find(environment: ["ASB_HERDR": "/bin/echo"]) == "/bin/echo")
}

@Test func herdrRunReturnsOutputAndGivesUpOnASlowCommand() {
    #expect(Herdr.run("/bin/echo", ["hello"], timeout: 2) == "hello\n")
    let start = Date()
    #expect(Herdr.run("/bin/sleep", ["5"], timeout: 0.3) == nil)
    #expect(Date().timeIntervalSince(start) < 2)
    #expect(Herdr.run("/usr/bin/false", [], timeout: 2) == nil)
}
