import Foundation
import Testing
@testable import ASBCore

private func tempDir() throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("asb-hooklog-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

private func lines(in dir: String) -> [[String: Any]] {
    let text = (try? String(contentsOfFile: dir + "/" + HookLog.fileName, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").compactMap {
        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    }
}

@Test func theSwitchIsOffUnlessTheConfigTurnsItOn() {
    #expect(!Config().debugHookLog)
    #expect(Config.parse("debug_hook_log=1\n").debugHookLog)
    #expect(!Config.parse("debug_hook_log=yes\n").debugHookLog)
}

@Test func aLineKeepsThePayloadTheParentAndTheHooksVariablesOnly() throws {
    let payload = Data(#"{"hook_event_name":"Notification","agent_id":"a1"}"#.utf8)
    let environment = ["HERDR_PANE_ID": "w2:p1", "HOME": "/Users/alex", "CLAUDE_CODE_ENTRYPOINT": "cli"]
    let line = HookLog.line(payload: payload, environment: environment, parentPid: 4242, now: 1_000)
    let entry = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    #expect(entry["at"] as? Int == 1_000)
    #expect(entry["ppid"] as? Int == 4242)
    #expect(entry["env"] as? [String: String] == ["HERDR_PANE_ID": "w2:p1", "CLAUDE_CODE_ENTRYPOINT": "cli"])
    #expect((entry["payload"] as? [String: String])?["agent_id"] == "a1")
    #expect(line.last == UInt8(ascii: "\n"))
}

@Test func aPayloadThatIsntJSONIsKeptAsText() throws {
    let line = HookLog.line(payload: Data("not json".utf8), environment: [:], parentPid: 1, now: 0)
    let entry = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    #expect(entry["payload"] as? String == "not json")
}

@Test func linesAreAppendedOnePerCall() throws {
    let dir = try tempDir()
    for n in 1...3 {
        HookLog.append(HookLog.line(payload: Data("{}".utf8), environment: [:], parentPid: 1, now: Int64(n)), stateDir: dir)
    }
    #expect(lines(in: dir).compactMap { $0["at"] as? Int } == [1, 2, 3])
}

@Test func nothingIsAppendedOnceTheLogReachesItsCap() throws {
    let dir = try tempDir()
    let line = HookLog.line(payload: Data("{}".utf8), environment: [:], parentPid: 1, now: 0)
    HookLog.append(line, stateDir: dir, maxBytes: line.count)
    HookLog.append(line, stateDir: dir, maxBytes: line.count)
    #expect(lines(in: dir).count == 1)
}
