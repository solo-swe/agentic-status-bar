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

@Test func aNewSubagentEndsAWaitOnTheAgentTool() throws {
    let waiting: [String: Any] = ["state": "waiting", "reason": "permission", "message": "Claude needs your permission",
                                  "lastTool": "Agent", "stateSince": 500]
    let s = written(apply(try payload("SubagentStart"), to: waiting, at: 2000))
    #expect(str(s, "state") == "busy" && !has(s, "reason") && !has(s, "message"))
    #expect(num(s, "stateSince") == 2000)
    #expect(str(written(apply(try payload("SubagentStart"), to: waiting.merging(["lastTool": "Task"]) { $1 }, at: 2000)), "state") == "busy")
}

@Test func otherSubagentStartsKeepTheWait() throws {
    let waiting: [String: Any] = ["state": "waiting", "reason": "permission", "lastTool": "Bash"]
    #expect(str(written(apply(try payload("SubagentStart"), to: waiting, at: 2000)), "state") == "waiting",
            "the prompt is for another tool")
    let resumed = waiting.merging(["lastTool": "Agent", "subagents": ["ac2ed88ebf4ec5d02": ["type": "general-purpose", "since": 1]]]) { $1 }
    #expect(str(written(apply(try payload("SubagentStart"), to: resumed, at: 2000)), "state") == "waiting",
            "a background subagent resuming is already listed")
    let older = waiting.merging(["lastTool": "Agent", "eventAt": 5000]) { $1 }
    #expect(str(written(apply(try payload("SubagentStart"), to: older, at: 6000, started: 4000)), "state") == "waiting",
            "an older start doesn't change the state")
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

@Test func anEventThatStartedBeforeTheLastOneIsDropped() throws {
    let p = try payload("Stop")
    #expect(apply(p, to: ["state": "busy", "eventAt": 5000], at: 6000, started: 4000) == .none)
    #expect(num(written(apply(p, to: ["state": "busy", "eventAt": 5000], at: 6000, started: 5000)), "eventAt") == 5000)
}

@Test func theRuleComparesEventStartsNotWriteTimes() throws {
    // PostToolUse started at 1000 and wrote at 1500; Stop started at 1200, between the two.
    let post = written(apply(try payload("PostToolUse"), to: ["state": "busy"], at: 1500, started: 1000))
    #expect(num(post, "eventAt") == 1000 && num(post, "updatedAt") == 1500)
    #expect(str(written(apply(try payload("Stop"), to: post, at: 1600, started: 1200)), "state") == "idle")
    // A file without eventAt (written before it existed) accepts the event, whatever its updatedAt.
    #expect(apply(try payload("Stop"), to: ["state": "busy", "updatedAt": 9000], at: 6000, started: 4000) != .none)
}

@Test func subagentsStartedTogetherAllLandInAnyOrder() throws {
    var state: [String: Any]? = ["state": "busy", "lastTool": "Agent"]
    // Three starts at 1000, 1001 and 1002 get the lock in reverse order.
    for (id, started) in [("c", Int64(1002)), ("b", 1001), ("a", 1000)] {
        var p = try payload("SubagentStart")
        p.agentId = id
        state = written(apply(p, to: state, at: 2000 + started, started: started))
    }
    #expect(Set((state?["subagents"] as? [String: Any] ?? [:]).keys) == ["a", "b", "c"])
    #expect(num(state, "eventAt") == 1002)
    // An older stop still removes its subagent, and leaves the state alone.
    var stop = try payload("SubagentStop")
    stop.agentId = "b"
    let after = written(apply(stop, to: (state ?? [:]).merging(["state": "idle"]) { $1 }, at: 4000, started: 900))
    #expect(Set((after?["subagents"] as? [String: Any] ?? [:]).keys) == ["a", "c"])
    #expect(str(after, "state") == "idle" && num(after, "eventAt") == 1002)
}

@Test func anOlderSubagentStartDoesNotSetTheState() throws {
    let s = written(apply(try payload("SubagentStart"), to: ["eventAt": 5000], at: 6000, started: 4000))
    #expect(!has(s, "state") && has(s, "subagents"))
}

// MARK: Background subagents (background_tasks)

private typealias BGTask = HookPayload.BackgroundTask

private func subagents(_ state: [String: Any]?) -> [String: [String: Any]] {
    (state?["subagents"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }
}

private func stop(_ agent: String, tasks: [BGTask]?) throws -> HookPayload {
    var p = try payload("SubagentStop")
    p.agentId = agent
    p.backgroundTasks = tasks
    return p
}

@Test func backgroundTasksAreRead() throws {
    let json = #"{"hook_event_name":"Stop","session_id":"s","background_tasks":[{"id":"a1","type":"subagent","status":"running","description":"d","agent_type":"Explore"},{"id":"b2","type":"shell","status":"running","command":"npm test"},{"type":"subagent"}]}"#
    let p = try #require(HookPayload.parse(Data(json.utf8)))
    #expect(p.backgroundTasks == [BGTask(id:"a1", type: "subagent", status: "running", agentType: "Explore"), BGTask(id:"b2", type: "shell")])
    #expect(try payload("Stop").backgroundTasks == [])
    #expect(HookPayload.parse(Data(#"{"hook_event_name":"Stop"}"#.utf8))?.backgroundTasks == nil)
}

@Test func onlySubagentsStillInFlightCount() {
    #expect(BGTask(id:"a", type: "subagent").isRunningSubagent)
    #expect(BGTask(id:"a", type: "subagent", status: "").isRunningSubagent)
    #expect(!BGTask(id:"a", type: "subagent", status: "completed").isRunningSubagent)
    #expect(!BGTask(id:"a", type: "shell").isRunningSubagent)
    #expect(!BGTask(id:"", type: "subagent").isRunningSubagent)
}

@Test func aBackgroundSubagentThatPausesStaysListed() throws {
    let start: [String: Any] = ["state": "idle", "subagents": ["a": ["type": "Explore", "since": 1000]]]
    let s = written(apply(try stop("a", tasks: [BGTask(id:"a", type: "subagent")]), to: start, at: 5000))
    #expect(num(subagents(s)["a"], "since") == 1000 && str(subagents(s)["a"], "type") == "Explore")
    #expect(subagents(s)["a"]?["background"] as? Bool == true)
    // Once the registry no longer lists it, its next stop removes it.
    #expect(!has(written(apply(try stop("a", tasks: []), to: s, at: 6000)), "subagents"))
}

@Test func aSubagentStopRefreshesTheBackgroundSubagentsFromTheRegistry() throws {
    let start: [String: Any] = ["state": "busy", "subagents": [
        "gone": ["type": "Explore", "since": 1000, "background": true],
        "fg": ["type": "Plan", "since": 1000],
        "a": ["type": "Explore", "since": 1000],
    ]]
    let tasks = [BGTask(id:"a", type: "subagent"), BGTask(id:"missed", type: "subagent", agentType: "general-purpose"),
                 BGTask(id:"sh", type: "shell")]
    let s = subagents(written(apply(try stop("a", tasks: tasks), to: start, at: 5000)))
    // A background agent that left the registry (killed) goes; a foreground one stays; a listed one
    // whose start was missed is added.
    #expect(Set(s.keys) == ["a", "fg", "missed"])
    #expect(str(s["missed"], "type") == "general-purpose" && num(s["missed"], "since") == 5000)
}

@Test func anOlderSubagentStopOnlyDecidesAboutItsOwnAgent() throws {
    let start: [String: Any] = ["eventAt": 9000, "subagents": [
        "a": ["type": "Explore", "since": 1000], "b": ["type": "Explore", "since": 1000, "background": true],
    ]]
    let s = subagents(written(apply(try stop("a", tasks: []), to: start, at: 9500, started: 8000)))
    #expect(Set(s.keys) == ["b"])
}

@Test func stopKeepsExactlyTheRunningBackgroundSubagents() throws {
    var p = try payload("Stop")
    p.backgroundTasks = [BGTask(id:"a", type: "subagent"), BGTask(id:"done", type: "subagent", status: "completed"),
                         BGTask(id:"sh", type: "shell")]
    let start: [String: Any] = ["state": "busy", "subagents": ["a": ["type": "Explore", "since": 1000], "fg": ["type": "Plan", "since": 1000]]]
    let s = written(apply(p, to: start, at: 5000))
    #expect(Set(subagents(s).keys) == ["a"] && num(subagents(s)["a"], "since") == 1000)
    p.backgroundTasks = []
    #expect(!has(written(apply(p, to: start, at: 5000)), "subagents"))
    // Without the registry Stop leaves the subagents alone.
    p.backgroundTasks = nil
    #expect(Set(subagents(written(apply(p, to: start, at: 5000))).keys) == ["a", "fg"])
}

@Test func withoutTheRegistryASubagentStopRemovesItsAgent() throws {
    let start: [String: Any] = ["subagents": ["a": ["type": "Explore", "since": 1000, "background": true]]]
    #expect(!has(written(apply(try stop("a", tasks: nil), to: start, at: 5000)), "subagents"))
}

@Test func aResumedSubagentKeepsItsFirstStart() throws {
    var p = try payload("SubagentStart")
    p.agentId = "a"
    let start: [String: Any] = ["state": "idle", "subagents": ["a": ["type": "Explore", "since": 1000, "background": true]]]
    let s = subagents(written(apply(p, to: start, at: 5000)))
    #expect(num(s["a"], "since") == 1000 && s["a"]?["background"] as? Bool == true)
}

@Test func unknownFieldsInTheStateAreKept() throws {
    #expect(str(try run(["Stop"], start: ["v": 1, "futureField": "kept"]).1, "futureField") == "kept")
}

@Test func unknownEventsChangeNothing() throws {
    var p = try payload("Stop")
    p.event = "PostToolUseFailure"
    #expect(apply(p, to: nil, at: 1000) == .none)
}

// MARK: Agents waiting on a prompt (PermissionRequest; spike T-119, tests/fixtures/README.md)

/// A fixture payload, changed where given: as agent `agent` ("" for the session's own), with these background
/// tasks, for tool `tool`.
private func event(_ name: String, agent: String? = nil, tasks: [String]? = nil, tool: String? = nil) throws -> HookPayload {
    var p = try payload(name)
    if let agent { p.agentId = agent; p.agentType = agent.isEmpty ? "" : "general-purpose" }
    if let tasks { p.backgroundTasks = tasks.map { BGTask(id: $0, type: "subagent") } }
    if let tool { p.toolName = tool }
    return p
}

/// Applies the payloads in order at 1000, 2000, ...; the state after each one.
private func play(_ events: [HookPayload], start: [String: Any]? = nil) -> [[String: Any]?] {
    var state = start
    return events.enumerated().map { i, p in
        if case .write(let s) = apply(p, to: state, at: Int64(i + 1) * 1000) { state = s }
        return state
    }
}

private func waiting(_ state: [String: Any]?) -> [String: String] {
    state?["waitingAgents"] as? [String: String] ?? [:]
}

private var busyWithTwo: [String: Any] { ["state": "busy", "subagents": [
    "a": ["type": "general-purpose", "since": 0, "background": true],
    "b": ["type": "general-purpose", "since": 0, "background": true],
]] }

@Test func aSubagentPermissionRequestSetsWaitingForThatAgent() throws {
    let s = play([try event("PermissionRequest-subagent", agent: "a")], start: busyWithTwo).last!
    #expect(str(s, "state") == "waiting" && str(s, "reason") == "permission")
    #expect(waiting(s) == ["a": "permission"] && str(s, "afterWaiting") == "busy")
    let question = play([try event("PermissionRequest-subagent", agent: "a", tool: "AskUserQuestion")], start: busyWithTwo)
    #expect(str(question.last!, "reason") == "question")
}

@Test func aSubagentWaitOutlastsOtherAgentsTheParentsStopAndTaskResults() throws {
    // The approved run the spike recorded: the other agent keeps working, the parent stops, then the permission
    // notification arrives without agent_id. A main-agent tool, a task result and an idle prompt are added; only
    // agent a's own PostToolUse ends the wait.
    let states = play([
        try event("PreToolUse-subagent", agent: "a"),
        try event("PermissionRequest-subagent", agent: "a"),
        try event("PreToolUse-subagent", agent: "b"),
        try event("PostToolUse-subagent", agent: "b"),
        try event("Stop", tasks: ["a", "b"]),
        try event("Notification-permission_prompt-subagent"),
        try event("PreToolUse", agent: ""),
        try event("UserPromptSubmit-task-notification"),
        try event("Notification-idle_prompt"),
        try event("PostToolUse-subagent", agent: "a"),
    ], start: busyWithTwo)
    for s in states[1...8] {
        #expect(str(s, "state") == "waiting" && str(s, "reason") == "permission" && waiting(s) == ["a": "permission"])
    }
    #expect(str(states[4], "afterWaiting") == "idle", "the parent's turn ended")
    #expect(str(states[5], "message") == "Claude needs your permission")
    #expect(str(states[8], "message") == "Claude needs your permission", "kept until the wait ends")
    #expect(num(states[8], "stateSince") == 2000, "waiting since the request")
    let done = states[9]
    #expect(str(done, "state") == "busy" && !has(done, "reason") && !has(done, "message"))
    #expect(!has(done, "waitingAgents") && !has(done, "afterWaiting"))
}

@Test func aDeniedSubagentThatEndsReturnsToTheParentsState() throws {
    // A denial fires no hook; the subagent ends (or carries on with another tool).
    let ended = play([
        try event("PermissionRequest-subagent", agent: "a"),
        try event("Stop", tasks: ["a", "b"]),
        try event("SubagentStop", agent: "a", tasks: ["b"]),
    ], start: busyWithTwo).last!
    #expect(str(ended, "state") == "idle" && !has(ended, "waitingAgents") && !has(ended, "reason"))
    let goesOn = play([
        try event("PermissionRequest-subagent", agent: "a"),
        try event("PreToolUse-subagent", agent: "a"),
    ], start: busyWithTwo).last!
    #expect(str(goesOn, "state") == "busy" && !has(goesOn, "waitingAgents"))
}

@Test func aWaitingSubagentTheRegistryNoLongerListsWaitsNoMore() throws {
    let s = play([
        try event("PermissionRequest-subagent", agent: "a"),
        try event("Stop", tasks: ["b"]),
    ], start: busyWithTwo).last!
    #expect(str(s, "state") == "idle" && !has(s, "waitingAgents"))
}

@Test func theSessionWaitsUntilEveryAgentIsAnswered() throws {
    let states = play([
        try event("PermissionRequest-subagent", agent: "a"),
        try event("PermissionRequest-subagent", agent: "b", tool: "AskUserQuestion"),
        try event("PostToolUse-subagent", agent: "a"),
        try event("PostToolUse-subagent", agent: "b"),
    ], start: busyWithTwo)
    #expect(waiting(states[1]) == ["a": "permission", "b": "question"])
    #expect(str(states[2], "state") == "waiting" && str(states[2], "reason") == "question")
    #expect(str(states[3], "state") == "busy")
}

@Test func theMainAgentsPermissionRequestWaitsThroughSubagentActivity() throws {
    let states = play([
        try event("PermissionRequest", agent: ""),
        try event("PostToolUse-subagent", agent: "a"),
        try event("PostToolUse", agent: ""),
    ], start: busyWithTwo)
    #expect(waiting(states[0]) == ["main": "permission"])
    #expect(str(states[1], "state") == "waiting")
    #expect(str(states[2], "state") == "busy" && !has(states[2], "waitingAgents"))
}

@Test func anApprovedAgentToolEndsTheMainAgentsWaitOnly() throws {
    var start = busyWithTwo
    start["lastTool"] = "Agent"
    let states = play([
        try event("PermissionRequest-subagent", agent: "a"),
        try event("PermissionRequest", agent: "", tool: "Agent"),
        try event("SubagentStart", agent: "c"),
    ], start: start)
    #expect(waiting(states[2]) == ["a": "permission"] && str(states[2], "state") == "waiting")
}

@Test func aPromptTheUserTypesOrANewSessionEndsEveryWait() throws {
    let waits = [try event("PermissionRequest-subagent", agent: "a")]
    let typed = play(waits + [try event("UserPromptSubmit")], start: busyWithTwo).last!
    #expect(str(typed, "state") == "busy" && !has(typed, "waitingAgents"))
    let cleared = play(waits + [try event("SessionStart")], start: busyWithTwo).last!
    #expect(str(cleared, "state") == "idle" && !has(cleared, "waitingAgents"))
}

@Test func withSeveralAgentsStillWaitingTheFirstByIdGivesTheReason() throws {
    let states = play([
        try event("PermissionRequest-subagent", agent: "b", tool: "AskUserQuestion"),
        try event("PermissionRequest-subagent", agent: "a"),
        try event("PreToolUse", agent: ""),
    ], start: busyWithTwo)
    #expect(waiting(states[2]) == ["a": "permission", "b": "question"])
    #expect(str(states[2], "state") == "waiting" && str(states[2], "reason") == "permission")
}

@Test func aWaitWithoutASavedStateReturnsToBusy() throws {
    // A file from before afterWaiting was written: the state to return to is unknown.
    let start: [String: Any] = ["state": "waiting", "reason": "permission", "waitingAgents": ["a": "permission"]]
    let states = play([
        try event("Notification-permission_prompt-subagent"),
        try event("PostToolUse-subagent", agent: "a"),
    ], start: start)
    #expect(str(states[0], "state") == "waiting" && str(states[0], "afterWaiting") == "busy")
    #expect(str(states[1], "state") == "busy" && !has(states[1], "waitingAgents"))
}

@Test func aSubagentStartWhileWaitingOnAnUnknownToolKeepsTheWait() throws {
    let s = written(apply(try payload("SubagentStart"), to: ["state": "waiting", "reason": "permission"], at: 5000))
    #expect(str(s, "state") == "waiting" && str(s, "reason") == "permission")
}

@Test func aSubagentStopWithoutAnySubagentsWritesNone() throws {
    let s = written(apply(try stop("a", tasks: nil), to: ["state": "busy"], at: 5000))
    #expect(str(s, "state") == "busy" && !has(s, "subagents"))
}

@Test func theFirstOfDuplicateBackgroundTasksWins() throws {
    let tasks = [BGTask(id: "a", type: "subagent", agentType: "Explore"), BGTask(id: "a", type: "subagent", agentType: "Plan")]
    let s = subagents(written(apply(try stop("a", tasks: tasks), to: ["state": "busy"], at: 5000)))
    #expect(str(s["a"], "type") == "Explore")
}

@Test func aBackgroundTaskWithoutATypeOrStatusReadsThemAsEmpty() throws {
    let p = try #require(HookPayload.parse(Data(#"{"hook_event_name":"Stop","background_tasks":[{"id":"a1"}]}"#.utf8)))
    #expect(p.backgroundTasks == [BGTask(id: "a1", type: "", status: "")])
}

@Test func valuesThatArentJSONAreNeverEqualAndAreDropped() {
    struct NotJSON {}
    #expect(!HookEvents.isEqualJSON(NotJSON(), NotJSON()))
    let s = HookEvents.hashable(["list": [1, "a", NotJSON()], "odd": NotJSON(), "n": 1])
    #expect(s == ["list": [1, "a"] as [AnyHashable], "n": 1])
}

@Test func withoutPermissionRequestTheNotificationWaitIsAsBefore() throws {
    // Hooks installed by an older version: no agent is known, so any tool event ends the wait.
    let states = play([
        try event("Notification-permission_prompt-subagent"),
        try event("PreToolUse-subagent", agent: "b"),
    ], start: busyWithTwo)
    #expect(str(states[0], "state") == "waiting" && !has(states[0], "waitingAgents"))
    #expect(str(states[1], "state") == "busy")
}

@Test func encodingIsOneLineWithSortedKeys() throws {
    guard case .write(let s) = apply(try payload("Stop"), to: nil, at: 7) else {
        Issue.record("expected a write")
        return
    }
    let text = String(decoding: HookEvents.encode(s), as: UTF8.self)
    #expect(text == #"{"eventAt":7,"sessionId":"3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90","state":"idle","stateSince":7,"updatedAt":7,"v":1}"#)
}
