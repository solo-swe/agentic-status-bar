import Foundation

/// An entry of Claude Code's own session registry (`~/.claude/sessions/<pid>.json`). The format is
/// undocumented, so everything is optional and checked before use.
public struct RegistryEntry: Equatable, Sendable {
    public var pid: Int32
    public var sessionId: String?
    /// The status, when it is a string; see `hasStatus`.
    public var status: String?
    /// False when the entry has no string `status` (a format change worth logging).
    public var hasStatus: Bool
    public var statusUpdatedAt: Int64?
    public var waitingFor: String?
    public var name: String?
    public var nameSource: String?

    /// Registry entries keyed by PID. Files that don't parse or have no `pid` are skipped; with two
    /// entries for one PID, the later file wins.
    public static func parse(_ files: [RawFile]) -> [Int32: RegistryEntry] {
        var entries: [Int32: RegistryEntry] = [:]
        for file in files {
            guard let object = try? JSONSerialization.jsonObject(with: file.contents) as? [String: Any],
                  let pidNumber = object["pid"] as? NSNumber, CFGetTypeID(pidNumber) != CFBooleanGetTypeID()
            else { continue }
            let pid = pidNumber.int32Value
            let status = object["status"] as? String
            entries[pid] = RegistryEntry(
                pid: pid,
                sessionId: object["sessionId"] as? String,
                status: status,
                hasStatus: status != nil,
                statusUpdatedAt: (object["statusUpdatedAt"] as? NSNumber).map { $0.int64Value },
                waitingFor: object["waitingFor"] as? String,
                name: object["name"] as? String,
                nameSource: object["nameSource"] as? String)
        }
        return entries
    }
}

extension Checks {
    /// C2: Claude Code's registry wins when it is newer than the state file. It also gives a session
    /// the name the user gave it (not one Claude Code derived). Only entries whose PID and session ID
    /// both match are used. Returns the sessions and whether an entry lacked a `status`.
    public static func registry(
        _ sessions: [ReconciledSession], entries: [Int32: RegistryEntry]
    ) -> (sessions: [ReconciledSession], schemaIssue: Bool) {
        var schemaIssue = false
        let result = sessions.map { session -> ReconciledSession in
            guard let pid = session.file.pid, let entry = entries[pid],
                  entry.sessionId == session.file.sessionId
            else { return session }
            var s = session
            if let name = entry.name, !name.isEmpty, entry.nameSource != "derived" {
                s.sessionName = name
            }
            guard let status = entry.status else {
                schemaIssue = true
                return s
            }
            guard let at = entry.statusUpdatedAt, at > (s.file.updatedAt ?? 0) else { return s }
            switch status {
            case "busy", "idle":
                s.shown = status
                s.shownSince = at
            case "waiting":
                s.shown = "waiting"
                s.shownSince = at
                s.reason = (entry.waitingFor ?? "").contains("permission") ? "permission" : "question"
            default:
                break
            }
            return s
        }
        return (result, schemaIssue)
    }
}
