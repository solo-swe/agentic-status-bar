import Foundation

/// A project's mute, keyed by its directory in the mutes file (doc/state-file-schema.md › Mutes file).
public struct Mute: Codable, Equatable, Sendable {
    /// Epoch ms when the mute ends.
    public var until: Int64
    /// Epoch ms when it was set: a prompt sent in the project after this lifts it.
    public var at: Int64
    /// Set by "Mute project for today".
    public var today: Bool

    public init(until: Int64, at: Int64, today: Bool) {
        self.until = until
        self.at = at
        self.today = today
    }
}

public enum Mutes {
    public static let fileName = "mutes"

    /// The mutes in a mutes file; a missing, corrupt or odd file counts as no mutes, and entries
    /// without a numeric `until` are skipped.
    public static func parse(_ text: String?) -> [String: Mute] {
        guard let text, let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return [:] }
        var mutes: [String: Mute] = [:]
        for (cwd, value) in object {
            guard let entry = value as? [String: Any], let until = (entry["until"] as? NSNumber)?.int64Value
            else { continue }
            mutes[cwd] = Mute(
                until: until, at: (entry["at"] as? NSNumber)?.int64Value ?? 0, today: entry["today"] as? Bool == true)
        }
        return mutes
    }

    /// The mutes in effect: not expired, and not lifted by a prompt sent in the project after the mute.
    public static func active(_ mutes: [String: Mute], sessions: [ReconciledSession], now: Int64) -> [String: Mute] {
        var lastPrompt: [String: Int64] = [:]
        for s in sessions {
            guard let cwd = s.file.cwd, let at = s.file.promptAt else { continue }
            lastPrompt[cwd] = max(lastPrompt[cwd] ?? at, at)
        }
        return mutes.filter { cwd, mute in mute.until > now && mute.at >= (lastPrompt[cwd] ?? 0) }
    }

    /// Marks the sessions of muted projects. A session waiting on the user still breaks through,
    /// so it keeps its mute details but isn't `muted`.
    public static func apply(_ sessions: [ReconciledSession], active: [String: Mute]) -> [ReconciledSession] {
        sessions.map { session in
            guard let cwd = session.file.cwd, let mute = active[cwd] else { return session }
            var s = session
            s.muteUntil = mute.until
            s.muteToday = mute.today
            s.muted = session.shown != "waiting"
            return s
        }
    }

    /// The next local midnight after `now`, epoch ms.
    public static func nextMidnight(after now: Int64, timeZone: TimeZone) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now) / 1000))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return Int64(tomorrow.timeIntervalSince1970 * 1000)
    }

    // MARK: Changes (the menu's mute actions)

    public static func muteHour(_ mutes: inout [String: Mute], cwd: String, now: Int64) {
        mutes[cwd] = Mute(until: now + 3_600_000, at: now, today: false)
    }

    public static func muteToday(_ mutes: inout [String: Mute], cwd: String, now: Int64, timeZone: TimeZone) {
        mutes[cwd] = Mute(until: nextMidnight(after: now, timeZone: timeZone), at: now, today: true)
    }

    /// The mutes file's text after a change, with expired mutes dropped. Keys are sorted.
    public static func encode(_ mutes: [String: Mute], now: Int64) -> String {
        let live = mutes.filter { $0.value.until > now }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(live)) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// Reads the mutes file, applies `change`, drops expired mutes and writes it atomically.
    public static func update(
        file: String, now: Int64, change: (inout [String: Mute]) -> Void
    ) throws {
        var mutes = parse(try? String(contentsOfFile: file, encoding: .utf8))
        change(&mutes)
        let url = URL(fileURLWithPath: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(encode(mutes, now: now).utf8).write(to: url, options: .atomic)
    }
}
