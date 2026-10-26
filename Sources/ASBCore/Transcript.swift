import Foundation

/// Reading the end of a Claude Code transcript (JSONL, undocumented format).
public enum Transcript {
    /// Bytes of each transcript the checks read: only the tail, never the whole file.
    public static let tailBytes = 8192
    /// What Claude Code writes when a turn is interrupted or a permission is denied
    /// (see tests/fixtures/README.md).
    public static let interruptMarker = "[Request interrupted by user"

    /// The JSON entries in the last `tailBytes` of a transcript. When the file is longer, the first
    /// line of the tail is cut and dropped. Lines that aren't JSON objects are skipped.
    public static func tailEntries(_ contents: Data) -> [[String: Any]] {
        var tail = contents.count > tailBytes ? contents.suffix(tailBytes) : contents[...]
        if contents.count > tailBytes {
            guard let newline = tail.firstIndex(of: UInt8(ascii: "\n")) else { return [] }
            tail = tail[tail.index(after: newline)...]
        }
        return tail.split(separator: UInt8(ascii: "\n")).compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
        }
    }

    /// The text of a user entry: its string content, or its text items joined by spaces.
    static func promptText(_ entry: [String: Any]) -> String {
        let content = (entry["message"] as? [String: Any])?["content"]
        if let text = content as? String { return text }
        if let items = content as? [[String: Any]] {
            return items.filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        return ""
    }

    /// A prompt the user (or a background task) sent: not a tool result, meta entry or interrupt marker.
    static func isPrompt(_ entry: [String: Any]) -> Bool {
        guard entry["type"] as? String == "user", entry["isMeta"] as? Bool != true else { return false }
        let content = (entry["message"] as? [String: Any])?["content"]
        let hasText = content is String
            || ((content as? [[String: Any]])?.contains { $0["type"] as? String == "text" } ?? false)
        return hasText && !promptText(entry).hasPrefix(interruptMarker)
    }

    /// An entry that ends a turn: Claude Code's turn timing, or the interrupt marker.
    static func endsTurn(_ entry: [String: Any]) -> Bool {
        let type = entry["type"] as? String
        return (type == "system" && entry["subtype"] as? String == "turn_duration")
            || (type == "user" && promptText(entry).hasPrefix(interruptMarker))
    }

    public enum TurnEnd: Equatable, Sendable {
        /// The turn finished normally (`turn_duration`): its Stop hook was missed.
        case finished
        /// The interrupt marker: Esc, or a denied permission. It can also stop subagents.
        case interrupted
    }

    /// How the turn after the latest prompt in `entries` ended; nil while it runs. An interrupt marker
    /// anywhere in it wins (Claude Code writes `turn_duration` after the marker too).
    public static func turnEnd(_ entries: [[String: Any]]) -> TurnEnd? {
        let afterPrompt = entries.lastIndex(where: isPrompt).map { entries[($0 + 1)...] } ?? entries[...]
        let ends = afterPrompt.filter(endsTurn)
        if ends.isEmpty { return nil }
        return ends.contains { $0["type"] as? String == "user" } ? .interrupted : .finished
    }

    /// Whether the turn after the latest prompt in `entries` has already ended.
    public static func turnEnded(_ entries: [[String: Any]]) -> Bool {
        turnEnd(entries) != nil
    }
}

extension Checks {
    /// C3: a busy or waiting session whose transcript shows that its turn already ended (Esc, or a
    /// denied permission, fire no hook; a Stop can be missed) is idle since its last update. Only an
    /// interrupt marks it `interrupted`, which keeps running subagents from showing: a turn that
    /// finished normally leaves its subagents running. Only sessions whose file says busy or waiting
    /// have their transcript read.
    public static func interrupts(
        _ sessions: [ReconciledSession], transcripts: [String: TranscriptInput]
    ) -> [ReconciledSession] {
        sessions.map { session in
            guard session.shown == "busy" || session.shown == "waiting",
                  readsTranscript(session.file),
                  let path = session.file.transcriptPath, let transcript = transcripts[path]
            else { return session }
            let entries = Transcript.tailEntries(transcript.contents)
            guard !entries.isEmpty, let end = Transcript.turnEnd(entries) else { return session }
            var s = session
            s.shown = "idle"
            s.shownSince = s.file.updatedAt
            s.interrupted = end == .interrupted
            return s
        }
    }

    /// Transcripts are read only for sessions whose file says busy or waiting (C3 and C5).
    public static func readsTranscript(_ file: StateFile) -> Bool {
        file.state == "busy" || file.state == "waiting"
    }
}
