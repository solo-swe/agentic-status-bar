import Foundation
import Testing
@testable import ASBCore

private let payloads = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/payloads")

private func payload(_ name: String) throws -> HookPayload {
    try #require(HookPayload.parse(Data(contentsOf: payloads.appendingPathComponent("\(name).json"))))
}

/// Applies fixture payloads in order, at times 1000, 2000, ...; returns the last outcome and the
/// state after all of them.
private func run(_ names: [String], start: [String: Any]? = nil, storePreview: Bool = true) throws -> (HookEvents.Outcome, [String: Any]?) {
    var state = start
    var outcome = HookEvents.Outcome.none
    for (i, name) in names.enumerated() {
        let t = Int64(i + 1) * 1000
        outcome = apply(try payload(name), to: state, at: t, storePreview: storePreview)
        switch outcome {
        case .write(let s): state = s
        case .delete: state = nil
        case .none: break
        }
    }
    return (outcome, state)
}

private func apply(_ p: HookPayload, to state: [String: Any]?, at t: Int64, started: Int64? = nil, storePreview: Bool = true) -> HookEvents.Outcome {
    HookEvents.apply(p, to: state, now: t, started: started ?? t, storePromptPreview: storePreview)
}

/// The written state of an outcome, or nil.
private func written(_ outcome: HookEvents.Outcome) -> [String: Any]? {
    if case .write(let s) = outcome { return s }
    return nil
}

private func str(_ state: [String: Any]?, _ key: String) -> String? { state?[key] as? String }
private func num(_ state: [String: Any]?, _ key: String) -> Int64? { (state?[key] as? NSNumber)?.int64Value }
private func has(_ state: [String: Any]?, _ key: String) -> Bool { state?[key] != nil }

@Test func payloadFieldsAreReadAsStrings() throws {
    let p = try payload("SubagentStop")
    #expect(p.event == "SubagentStop" && p.sessionId == "3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90")
    #expect(p.agentId == "ac2ed88ebf4ec5d02" && p.agentType == "general-purpose")
    #expect(p.cwd == "/Users/alex/code/api-gateway")
    #expect(HookPayload.parse(Data(#"{"hook_event_name":"X","session_id":42}"#.utf8))?.sessionId == "42")
    #expect(HookPayload.parse(Data("not json".utf8)) == nil)
    #expect(HookPayload.parse(Data("[1]".utf8)) == nil)
}

@Test func sessionStartWritesAnIdleState() throws {
    let (_, s) = try run(["SessionStart"])
    #expect(str(s, "state") == "idle" && num(s, "v") == 1)
    #expect(str(s, "sessionId") == "3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90")
    #expect(num(s, "updatedAt") == 1000 && num(s, "stateSince") == 1000)
}

@Test func sessionStartAfterCompactionKeepsTheCurrentState() throws {
    var compact = try payload("SessionStart")
    compact.source = "compact"
    let busy: [String: Any] = ["v": 1, "state": "busy", "reason": "x", "updatedAt": 500, "stateSince": 400]
    let s = written(apply(compact, to: busy, at: 1000))
    #expect(str(s, "state") == "busy" && num(s, "stateSince") == 400 && str(s, "reason") == "x")
}

@Test func sessionStartOnStartupResetsAnExistingState() throws {
    let waiting: [String: Any] = ["v": 1, "state": "waiting", "reason": "permission", "message": "m",
                                  "subagents": ["a": ["type": "x", "since": 1]], "updatedAt": 500]
    let (_, s) = try run(["SessionStart"], start: waiting)
    #expect(str(s, "state") == "idle")
    #expect(!has(s, "reason") && !has(s, "message") && !has(s, "subagents"))
}

@Test func userPromptSubmitSetsBusyAndStoresThePreview() throws {
    let (_, s) = try run(["SessionStart", "UserPromptSubmit"])
    #expect(str(s, "state") == "busy")
    #expect(str(s, "promptPreview") == "Add rate limiting to the auth routes")
    #expect(num(s, "promptAt") == 2000)
}

@Test func thePreviewCollapsesWhitespaceAndKeeps80Characters() {
    #expect(HookEvents.preview("  hello \n\t world  ") == "hello world ")
    #expect(HookEvents.preview(String(repeating: "abcdefghij", count: 10)).count == 80)
    #expect(HookEvents.preview(String(repeating: "é", count: 100)).unicodeScalars.count == 80)
}

@Test func aBackgroundTaskNotificationKeepsThePreviewAndPromptTime() throws {
    let (_, s) = try run(["UserPromptSubmit", "UserPromptSubmit-task-notification"])
    #expect(str(s, "state") == "busy")
    #expect(str(s, "promptPreview") == "Add rate limiting to the auth routes")
    #expect(num(s, "promptAt") == 1000)
}

@Test func noPreviewIsStoredWhenStorePromptPreviewIs0() throws {
    let (_, s) = try run(["UserPromptSubmit"], start: ["promptPreview": "old"], storePreview: false)
    #expect(str(s, "state") == "busy" && !has(s, "promptPreview"))
}

@Test func preToolUseSetsBusyRecordsTheToolAndClearsWaitingDetails() throws {
    let (_, s) = try run(["Notification-permission_prompt", "PreToolUse"])
    #expect(str(s, "state") == "busy" && str(s, "lastTool") == "Bash")
    #expect(!has(s, "reason") && !has(s, "message"))
}

@Test func postToolUseSetsBusyAndKeepsLastTool() throws {
    let (_, s) = try run(["PreToolUse", "Stop", "PostToolUse"])
    #expect(str(s, "state") == "busy" && str(s, "lastTool") == "Bash")
}

@Test func stateSinceOnlyChangesWhenTheStateChanges() throws {
    let (_, s) = try run(["UserPromptSubmit", "PreToolUse", "PostToolUse"])
    #expect(num(s, "stateSince") == 1000 && num(s, "updatedAt") == 3000)
}

@Test func aPermissionPromptSetsWaitingWithReasonPermission() throws {
    let (_, s) = try run(["PreToolUse", "Notification-permission_prompt"])
    #expect(str(s, "state") == "waiting" && str(s, "reason") == "permission")
    #expect(str(s, "message") == "Claude needs your permission")
}

@Test func aPermissionPromptAfterAskUserQuestionIsAQuestion() throws {
    let (_, s) = try run(["PreToolUse-AskUserQuestion", "Notification-permission_prompt"])
    #expect(str(s, "state") == "waiting" && str(s, "reason") == "question")
}

@Test func anElicitationDialogIsAQuestion() throws {
    var p = try payload("Notification-permission_prompt")
    p.notificationType = "elicitation_dialog"
    p.message = "An MCP server needs input"
    let s = written(apply(p, to: nil, at: 1))
    #expect(str(s, "state") == "waiting" && str(s, "reason") == "question" && str(s, "message") == "An MCP server needs input")
}

@Test func anIdlePromptSetsIdle() throws {
    let (_, s) = try run(["UserPromptSubmit", "Notification-idle_prompt"])
    #expect(str(s, "state") == "idle")
}

@Test func withoutANotificationTypeTheMessageTextDecides() throws {
    var p = try payload("Notification-permission_prompt")
    p.notificationType = ""
    p.message = "Claude needs your permission to use Bash"
    let waiting = written(apply(p, to: nil, at: 1))
    #expect(str(waiting, "state") == "waiting" && str(waiting, "reason") == "permission")
    p.message = "Claude is waiting for your input"
    #expect(str(written(apply(p, to: nil, at: 1)), "state") == "idle")
}

@Test func anUnknownNotificationTypeChangesNothing() throws {
    var p = try payload("Notification-permission_prompt")
    p.notificationType = "auth_success"
    #expect(apply(p, to: ["state": "busy"], at: 1) == .none)
}

@Test func stopSetsIdleAndClearsWaitingDetails() throws {
    let (_, s) = try run(["Notification-permission_prompt", "Stop"])
    #expect(str(s, "state") == "idle" && !has(s, "reason") && !has(s, "message"))
}

@Test func sessionEndDeletesTheFile() throws {
    let (outcome, s) = try run(["SessionStart", "SessionEnd"])
    #expect(outcome == .delete && s == nil)
}

@Test func subagentStartAddsTheSubagentWithoutChangingTheState() throws {
    let (_, s) = try run(["Stop", "SubagentStart"])
    #expect(str(s, "state") == "idle")
    let agent = (s?["subagents"] as? [String: Any])?["ac2ed88ebf4ec5d02"] as? [String: Any]
    #expect(str(agent, "type") == "general-purpose" && num(agent, "since") == 2000)
}

@Test func subagentStartOnANewFileSetsBusy() throws {
    #expect(str(try run(["SubagentStart"]).1, "state") == "busy")
}

@Test func subagentStopRemovesTheSubagentAndKeepsOthers() throws {
    var other = try payload("SubagentStart")
    other.agentId = "other"
    let two = written(apply(other, to: try run(["SubagentStart"]).1, at: 5000))
    let s = written(apply(try payload("SubagentStop"), to: two, at: 6000))
    #expect(Array((s?["subagents"] as? [String: Any] ?? [:]).keys) == ["other"])
    #expect(!has(try run(["SubagentStart", "SubagentStop"]).1, "subagents"))
}

@Test func theEmptySubagentStopAfterStopIsIgnored() throws {
    #expect(try run(["SubagentStart", "SubagentStop-empty"]).0 == .none)
}

@Test func subagentStartWithoutAnAgentIdIsIgnored() throws {
    var p = try payload("SubagentStart")
    p.agentId = ""
    #expect(apply(p, to: nil, at: 1) == .none)
}

@Test func anEventOlderThanTheStoredUpdateIsDropped() throws {
    let p = try payload("Stop")
    #expect(apply(p, to: ["state": "busy", "updatedAt": 5000], at: 6000, started: 4000) == .none)
    #expect(apply(p, to: ["state": "busy", "updatedAt": 5000], at: 6000, started: 5000) != .none)
}

@Test func unknownFieldsInTheStateAreKept() throws {
    #expect(str(try run(["Stop"], start: ["v": 1, "futureField": "kept"]).1, "futureField") == "kept")
}

@Test func unknownEventsChangeNothing() throws {
    #expect(try run(["PermissionRequest"]).0 == .none)
}

@Test func encodingIsOneLineWithSortedKeys() throws {
    guard case .write(let s) = apply(try payload("Stop"), to: nil, at: 7) else {
        Issue.record("expected a write")
        return
    }
    let text = String(decoding: HookEvents.encode(s), as: UTF8.self)
    #expect(text == #"{"sessionId":"3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90","state":"idle","stateSince":7,"updatedAt":7,"v":1}"#)
}
