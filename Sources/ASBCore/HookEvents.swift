import Foundation

/// The fields of a Claude Code hook payload the hook uses. Every field is a string; a missing one is
/// "", a non-string one is its JSON text (as the shell hook's jq did).
public struct HookPayload: Equatable, Sendable {
    public var event = ""
    public var sessionId = ""
    public var cwd = ""
    public var transcriptPath = ""
    public var source = ""
    public var prompt = ""
    public var toolName = ""
    public var notificationType = ""
    public var message = ""
    public var agentId = ""
    public var agentType = ""
    /// Stop and SubagentStop: the parent session's in-flight background tasks; nil when the payload
    /// has none (older Claude Code, or the task registry wasn't reachable).
    public var backgroundTasks: [BackgroundTask]?

    public init() {}

    /// One entry of `background_tasks` (hooks docs › Stop input).
    public struct BackgroundTask: Equatable, Sendable {
        public var id: String
        /// `subagent`, `shell`, `monitor`, `workflow`, ...
        public var type: String
        public var status: String
        public var agentType: String

        public init(id: String, type: String, status: String = "running", agentType: String = "") {
            self.id = id
            self.type = type
            self.status = status
            self.agentType = agentType
        }

        /// Statuses of a task that is no longer in flight, should the registry still list one.
        static let finished: Set = ["completed", "failed", "killed", "stopped", "cancelled", "canceled", "error"]

        public var isRunningSubagent: Bool {
            type == "subagent" && !id.isEmpty && !Self.finished.contains(status.lowercased())
        }
    }

    /// Nil when the input isn't a JSON object.
    public static func parse(_ data: Data) -> HookPayload? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func s(_ key: String) -> String {
            switch object[key] {
            case nil, is NSNull: return ""
            case let string as String: return string
            case let value?:
                if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) {
                    return String(decoding: data, as: UTF8.self)
                }
                return ""
            }
        }
        var p = HookPayload()
        p.event = s("hook_event_name")
        p.sessionId = s("session_id")
        p.cwd = s("cwd")
        p.transcriptPath = s("transcript_path")
        p.source = s("source")
        p.prompt = s("prompt")
        p.toolName = s("tool_name")
        p.notificationType = s("notification_type")
        p.message = s("message")
        p.agentId = s("agent_id")
        p.agentType = s("agent_type")
        if let tasks = object["background_tasks"] as? [Any] {
            p.backgroundTasks = tasks.compactMap { entry in
                guard let task = entry as? [String: Any], let id = task["id"] as? String else { return nil }
                return BackgroundTask(
                    id: id, type: task["type"] as? String ?? "", status: task["status"] as? String ?? "",
                    agentType: task["agent_type"] as? String ?? "")
            }
        }
        return p
    }
}

/// How one hook event changes a session's state file (doc/state-file-schema.md › Events).
public enum HookEvents {
    /// Prompts that start with this are background-task results, not something the user typed.
    public static let taskNotificationPrefix = "<task-notification>"
    /// Characters of the prompt kept as the row title fallback.
    public static let previewLength = 80

    public enum Outcome: Equatable {
        /// Write this state (the full object).
        case write([String: AnyHashable])
        /// Delete the state file.
        case delete
        /// Leave the file as it is.
        case none
    }

    /// Applies `payload` to the current state (`current`: the parsed file, or nil when missing or
    /// corrupt). `started` is when the hook started (epoch ms). An event that started before the
    /// last applied one (`eventAt`) is dropped, so async hooks finishing out of order can't go back
    /// in time; subagent events still add or remove their subagent, since that map is keyed by agent
    /// ID and its order doesn't matter.
    public static func apply(
        _ payload: HookPayload, to current: [String: Any]?, now: Int64, started: Int64,
        storePromptPreview: Bool, sessionStartChanges: (inout [String: Any]) -> Void = { _ in }
    ) -> Outcome {
        if payload.event == "SessionEnd" { return .delete }
        let old = current ?? [:]
        let lastEvent = (old["eventAt"] as? NSNumber)?.int64Value
        let older = lastEvent.map { $0 > started } ?? false
        if older && payload.event != "SubagentStart" && payload.event != "SubagentStop" { return .none }

        var s = old
        switch payload.event {
        case "SessionStart":
            sessionStartChanges(&s)
            if !(payload.source == "compact" && s["state"] != nil && !(s["state"] is NSNull)) {
                s["state"] = "idle"
                s["reason"] = nil
                s["message"] = nil
                s["subagents"] = nil
            }
        case "UserPromptSubmit":
            s["state"] = "busy"
            s["reason"] = nil
            s["message"] = nil
            let fromTask = payload.prompt.hasPrefix(taskNotificationPrefix)
            if storePromptPreview && !fromTask && !payload.prompt.isEmpty {
                s["promptPreview"] = preview(payload.prompt)
            } else if !storePromptPreview {
                s["promptPreview"] = nil
            }
            if !fromTask { s["promptAt"] = now }
        case "PreToolUse":
            s["state"] = "busy"
            s["reason"] = nil
            s["message"] = nil
            s["lastTool"] = payload.toolName
        case "PostToolUse":
            s["state"] = "busy"
            s["reason"] = nil
            s["message"] = nil
        case "Notification":
            var type = payload.notificationType
            if type.isEmpty {
                // Older payloads may lack notification_type: the message text decides.
                if payload.message.contains("needs your permission") { type = "permission_prompt" }
                else if payload.message.contains("waiting for your input") { type = "idle_prompt" }
            }
            switch type {
            case "permission_prompt":
                // AskUserQuestion questions also arrive as permission prompts.
                s["state"] = "waiting"
                s["reason"] = s["lastTool"] as? String == "AskUserQuestion" ? "question" : "permission"
                s["message"] = payload.message
            case "elicitation_dialog":
                s["state"] = "waiting"
                s["reason"] = "question"
                s["message"] = payload.message
            case "idle_prompt":
                s["state"] = "idle"
                s["reason"] = nil
                s["message"] = nil
            default:
                return .none
            }
        case "Stop":
            s["state"] = "idle"
            s["reason"] = nil
            s["message"] = nil
            // No foreground subagent runs while the main agent stops: the running subagents are
            // exactly the background ones the task registry lists.
            if let tasks = payload.backgroundTasks {
                let old = s["subagents"] as? [String: Any] ?? [:]
                var agents: [String: Any] = [:]
                for task in tasks where task.isRunningSubagent {
                    agents[task.id] = backgroundEntry(task, old: old[task.id], now: now)
                }
                s["subagents"] = agents.isEmpty ? nil : agents
            }
        case "SubagentStart":
            guard !payload.agentId.isEmpty else { return .none }
            if !older, s["state"] == nil || s["state"] is NSNull || (s["state"] as? Bool) == false { s["state"] = "busy" }
            var agents = s["subagents"] as? [String: Any] ?? [:]
            // A resumed subagent keeps its entry (and first start time).
            if agents[payload.agentId] == nil {
                agents[payload.agentId] = ["type": payload.agentType.isEmpty ? "agent" : payload.agentType, "since": now]
            }
            s["subagents"] = agents
        case "SubagentStop":
            // An extra SubagentStop with an empty agent_type follows every Stop; it has no matching start.
            guard !payload.agentId.isEmpty, !payload.agentType.isEmpty else { return .none }
            var agents = s["subagents"] as? [String: Any] ?? [:]
            if let tasks = payload.backgroundTasks {
                let running = Dictionary(
                    tasks.filter(\.isRunningSubagent).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                // A background subagent stops each time it pauses for its own background work; it
                // has finished only when the registry no longer lists it.
                agents[payload.agentId] = running[payload.agentId].map {
                    backgroundEntry($0, old: agents[payload.agentId], now: now)
                }
                if !older {
                    // Other background subagents that left the registry finished (a kill fires no
                    // SubagentStop); foreground ones are never in it and are left alone.
                    for (id, entry) in agents where id != payload.agentId && running[id] == nil
                        && (entry as? [String: Any])?["background"] as? Bool == true {
                        agents[id] = nil
                    }
                    for task in running.values where agents[task.id] == nil {
                        agents[task.id] = backgroundEntry(task, old: nil, now: now)
                    }
                }
            } else {
                agents[payload.agentId] = nil
            }
            s["subagents"] = agents.isEmpty ? nil : agents
        default:
            return .none
        }
        return .write(stamped(s, old: old, sessionId: payload.sessionId, now: now, eventAt: max(started, lastEvent ?? started)))
    }

    /// Sets v, sessionId, updatedAt and eventAt, and stateSince when the state changed (or was never set).
    static func stamped(
        _ new: [String: Any], old: [String: Any], sessionId: String, now: Int64, eventAt: Int64
    ) -> [String: AnyHashable] {
        var s = new
        s["v"] = 1
        s["sessionId"] = sessionId
        s["updatedAt"] = now
        s["eventAt"] = eventAt
        let changed = !isEqualJSON(s["state"], old["state"])
        if changed || s["stateSince"] == nil || s["stateSince"] is NSNull { s["stateSince"] = now }
        return hashable(s)
    }

    /// A `subagents` entry for a background subagent the task registry lists: its existing entry's
    /// type and start time when there is one, marked `background`.
    static func backgroundEntry(_ task: HookPayload.BackgroundTask, old: Any?, now: Int64) -> [String: Any] {
        var entry = old as? [String: Any] ?? [:]
        if entry["type"] as? String == nil { entry["type"] = task.agentType.isEmpty ? "agent" : task.agentType }
        if entry["since"] == nil { entry["since"] = now }
        entry["background"] = true
        return entry
    }

    /// The first 80 characters of a prompt, runs of whitespace collapsed to one space, no leading space.
    public static func preview(_ prompt: String) -> String {
        var collapsed = prompt.replacing(/\s+/, with: " ")
        if collapsed.hasPrefix(" ") { collapsed.removeFirst() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: collapsed.unicodeScalars.prefix(previewLength))
        return String(view)
    }

    static func isEqualJSON(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as? NSObject)?.isEqual(b) ?? false
        default: return false
        }
    }

    /// The JSON object as hashable values (outcomes can be compared in tests).
    public static func hashable(_ object: [String: Any]) -> [String: AnyHashable] {
        object.compactMapValues(hashableValue)
    }

    private static func hashableValue(_ value: Any) -> AnyHashable? {
        switch value {
        case let dict as [String: Any]: return hashable(dict) as AnyHashable
        case let array as [Any]: return array.compactMap(hashableValue) as AnyHashable
        case let h as AnyHashable: return h
        default: return nil
        }
    }

    /// One-line JSON for a state file.
    public static func encode(_ state: [String: AnyHashable]) -> Data {
        (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }
}
