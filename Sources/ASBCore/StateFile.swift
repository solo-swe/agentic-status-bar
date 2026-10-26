import Foundation

/// One session's state file (doc/state-file-schema.md). Decoding is lenient: unknown fields are
/// ignored and a field of the wrong type counts as absent, so one odd field never hides a session.
public struct StateFile: Equatable, Sendable {
    /// Highest schema version this code understands.
    public static let maxVersion = 1

    public var path: String
    public var v: Int
    public var sessionId: String
    public var state: String?
    public var reason: String?
    public var message: String?
    public var updatedAt: Int64?
    public var stateSince: Int64?
    public var pid: Int32?
    public var procStart: String?
    public var cwd: String?
    public var kind: String?
    public var termBundleId: String?
    public var herdrPane: String?
    public var transcriptPath: String?
    public var lastTool: String?
    public var promptPreview: String?
    public var promptAt: Int64?
    public var subagents: [String: Subagent]

    public struct Subagent: Equatable, Sendable {
        public var type: String
        public var since: Int64?

        public init(type: String, since: Int64?) {
            self.type = type
            self.since = since
        }
    }

    public init(path: String, v: Int = 1, sessionId: String) {
        self.path = path
        self.v = v
        self.sessionId = sessionId
        self.subagents = [:]
    }

    /// Parses a state file; nil when it is invalid (not JSON, not an object, or `v` missing, not a
    /// number or outside 1...maxVersion). A missing `sessionId` falls back to the file name.
    public static func parse(_ file: RawFile) -> StateFile? {
        guard let object = try? JSONSerialization.jsonObject(with: file.contents) as? [String: Any],
              let v = number(object["v"]).map(Int.init), (1...maxVersion).contains(v)
        else { return nil }

        let fallbackId = ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension
        var s = StateFile(path: file.path, v: v, sessionId: object["sessionId"] as? String ?? fallbackId)
        s.state = object["state"] as? String
        s.reason = object["reason"] as? String
        s.message = object["message"] as? String
        s.updatedAt = number(object["updatedAt"]).map(Int64.init)
        s.stateSince = number(object["stateSince"]).map(Int64.init)
        s.pid = number(object["pid"]).map(Int32.init)
        s.procStart = object["procStart"] as? String
        s.cwd = object["cwd"] as? String
        s.kind = object["kind"] as? String
        s.termBundleId = object["termBundleId"] as? String
        s.herdrPane = object["herdrPane"] as? String
        s.transcriptPath = object["transcriptPath"] as? String
        s.lastTool = object["lastTool"] as? String
        s.promptPreview = object["promptPreview"] as? String
        s.promptAt = number(object["promptAt"]).map(Int64.init)
        if let agents = object["subagents"] as? [String: Any] {
            for (id, value) in agents {
                guard let agent = value as? [String: Any] else { continue }
                s.subagents[id] = Subagent(
                    type: agent["type"] as? String ?? "agent", since: number(agent["since"]).map(Int64.init))
            }
        }
        return s
    }

    /// A JSON number (not a boolean) as a Double.
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite && abs(d) < 9.2e18 ? d : nil
    }
}

/// The state files of a state dir, parsed.
public struct ParsedStates: Equatable, Sendable {
    public var sessions: [StateFile]
    /// Files that couldn't be read: shown as a warning, never deleted.
    public var invalidCount: Int

    public static func parse(_ files: [RawFile]) -> ParsedStates {
        var sessions: [StateFile] = []
        var invalid = 0
        for file in files {
            if let state = StateFile.parse(file) { sessions.append(state) } else { invalid += 1 }
        }
        return ParsedStates(sessions: sessions, invalidCount: invalid)
    }
}

/// Reading state files from disk.
public enum StateDirectory {
    /// The `*.json` regular files in `dir`, sorted by name. Temp files (`*.json.tmp.*`) and lock
    /// directories (`*.json.lock`) don't end in `.json`, so they are skipped. A missing dir gives [].
    public static func read(_ dir: String) -> [RawFile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            let path = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
                  let data = fm.contents(atPath: path) else { return nil }
            return RawFile(path: path, contents: data)
        }
    }
}
