import Foundation
import Testing
@testable import ASBCore

private let payloads = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/payloads")
/// The session ID of the fixture payloads.
private let sessionId = "3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90"

/// The hook (pid 5001) runs under a shell (5000) under claude (4242).
private let tree = FakeProcessInspector([
    ProcessRecord(pid: 5001, ppid: 5000, start: 1_792_426_383, comm: "asb", args: "asb hook"),
    ProcessRecord(pid: 5000, ppid: 4242, start: 1_792_426_383, comm: "/bin/sh", args: "sh -c asb hook"),
    ProcessRecord(pid: 4242, ppid: 1, start: 1_792_426_323, comm: "claude", args: "claude"),
])

/// A temporary home whose state dir and config the hook is pointed at through the `ASB_*` overrides.
private struct HookHome {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("asb-hook-\(UUID().uuidString)").path
    var stateDir: String { root + "/state" }
    var configFile: String { root + "/config" }
    var stateFile: String { "\(stateDir)/\(sessionId).json" }
    var environment: [String: String] { ["HOME": root, "ASB_STATE_DIR": stateDir, "ASB_CONFIG": configFile] }

    init(config: String = "") throws {
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try Data(config.utf8).write(to: URL(fileURLWithPath: configFile))
    }

    func handle(
        _ input: Data, started: Int64 = 1_000, now: Int64 = 1_500, inspector: any ProcessInspector = tree
    ) {
        Hook.handle(input, started: started, environment: environment, parentPid: 5000, inspector: inspector, now: { now })
    }

    func handle(_ fixture: String, started: Int64 = 1_000, now: Int64 = 1_500, inspector: any ProcessInspector = tree) throws {
        handle(try payload(fixture), started: started, now: now, inspector: inspector)
    }

    func state(_ file: String? = nil) -> [String: Any]? {
        Hook.readState(file ?? stateFile)
    }

    func write(_ state: [String: Any], to name: String = "\(sessionId).json") throws {
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state).write(to: URL(fileURLWithPath: "\(stateDir)/\(name)"))
    }

    func files() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: stateDir)) ?? []
    }
}

private func payload(_ name: String) throws -> Data {
    try Data(contentsOf: payloads.appendingPathComponent("\(name).json"))
}

@Test func anEventIsWrittenToTheSessionsStateFileWithTheStartAndTheTimeOfTheWrite() throws {
    let home = try HookHome()
    try home.handle("PreToolUse", started: 1_000, now: 1_500)
    let state = try #require(home.state())
    #expect(state["v"] as? Int == 1 && state["sessionId"] as? String == sessionId)
    #expect(state["state"] as? String == "busy" && state["lastTool"] as? String == "Bash")
    #expect(state["eventAt"] as? Int == 1_000 && state["updatedAt"] as? Int == 1_500)
    #expect(home.files() == ["\(sessionId).json"])
}

@Test func aSessionThatPredatesTheHooksIsBackfilledFromTheProcessTable() throws {
    let home = try HookHome()
    try home.write(["v": 1, "sessionId": sessionId, "state": "idle"])
    try home.handle("PreToolUse")
    let state = try #require(home.state())
    #expect(state["pid"] as? Int == 4242 && state["kind"] as? String == "interactive")
    #expect(state["cwd"] as? String == "/Users/alex/code/api-gateway")
}

@Test func aSessionWithItsDetailsRecordedIsNotLookedUpAgain() throws {
    let home = try HookHome()
    try home.handle("SessionStart", started: 1_000)
    try home.handle("PreToolUse", started: 2_000, inspector: FakeProcessInspector())
    #expect(home.state()?["pid"] as? Int == 4242)
}

@Test func sessionEndDeletesTheStateFile() throws {
    let home = try HookHome()
    try home.handle("SessionStart", started: 1_000)
    try home.handle("SessionEnd", started: 2_000)
    #expect(home.files().isEmpty)
}

@Test func anEventThatStartedBeforeTheLastAppliedOneIsDropped() throws {
    let home = try HookHome()
    try home.handle("PreToolUse", started: 2_000, now: 2_100)
    try home.handle("Stop", started: 1_000, now: 2_200)
    let state = try #require(home.state())
    #expect(state["state"] as? String == "busy" && state["updatedAt"] as? Int == 2_100)
}

@Test func sessionStartRemovesTheFilesLeftForTheSameProcess() throws {
    let home = try HookHome()
    try home.write(["v": 1, "sessionId": "before-clear", "pid": 4242], to: "before-clear.json")
    try home.write(["v": 1, "sessionId": "other-claude", "pid": 777], to: "other-claude.json")
    try home.handle("SessionStart")
    #expect(home.files().sorted() == ["\(sessionId).json", "other-claude.json"])
}

@Test func otherEventsLeaveTheFilesOfTheSameProcessAlone() throws {
    let home = try HookHome()
    try home.write(["v": 1, "sessionId": "before-clear", "pid": 4242], to: "before-clear.json")
    try home.handle("PreToolUse")
    #expect(home.files().sorted() == ["\(sessionId).json", "before-clear.json"])
}

@Test func theDebugLogKeepsEveryPayloadWhenTheConfigTurnsItOn() throws {
    let home = try HookHome(config: "debug_hook_log=1\n")
    try home.handle("PreToolUse", started: 1_000)
    home.handle(Data("not json".utf8), started: 2_000)
    let text = try String(contentsOfFile: "\(home.stateDir)/\(HookLog.fileName)", encoding: .utf8)
    let entries = text.split(separator: "\n").compactMap {
        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
    #expect(entries.compactMap { $0["at"] as? Int } == [1_000, 2_000])
    #expect(entries.allSatisfy { $0["ppid"] as? Int == 5000 })
    #expect(entries.last?["payload"] as? String == "not json")
}

@Test func theDebugLogIsOffByDefault() throws {
    let home = try HookHome()
    try home.handle("PreToolUse")
    #expect(!home.files().contains(HookLog.fileName))
}

@Test(arguments: [
    Data("not json".utf8),
    Data(#"{"session_id":"abc"}"#.utf8),
    Data(#"{"session_id":"../escape","hook_event_name":"Stop"}"#.utf8),
    Data(#"{"session_id":"","hook_event_name":"Stop"}"#.utf8),
])
func aPayloadThatIsInvalidOrHasAnUnsafeSessionIdWritesNothing(_ input: Data) throws {
    let home = try HookHome()
    home.handle(input)
    #expect(home.files().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: "\(home.root)/escape.json"))
}

@Test func theClockDefaultsToTheTimeNow() throws {
    let home = try HookHome()
    let before = Hook.epochMilliseconds()
    Hook.handle(try payload("Stop"), started: before, environment: home.environment, parentPid: 5000,
                inspector: FakeProcessInspector())
    let updatedAt = try #require(home.state()?["updatedAt"] as? Int)
    #expect(Int64(updatedAt) >= before && Int64(updatedAt) <= Hook.epochMilliseconds())
}
