import Foundation

/// Reads the process table. The macOS implementation uses libproc (ProcessesDarwin.swift);
/// tests use `FakeProcessInspector`.
public protocol ProcessInspector: Sendable {
    /// Every process, without arguments (cheap enough for every refresh).
    func processes() -> [ProcessRecord]
    /// One process, without arguments; nil when it doesn't exist.
    func process(_ pid: Int32) -> ProcessRecord?
    /// A process's full command line, or nil when it can't be read.
    func arguments(_ pid: Int32) -> String?
}

public struct FakeProcessInspector: ProcessInspector {
    public var records: [ProcessRecord]

    public init(_ records: [ProcessRecord] = []) {
        self.records = records
    }

    public func processes() -> [ProcessRecord] {
        records.map { var r = $0; r.args = nil; return r }
    }

    public func process(_ pid: Int32) -> ProcessRecord? {
        records.first { $0.pid == pid }.map { var r = $0; r.args = nil; return r }
    }

    public func arguments(_ pid: Int32) -> String? {
        records.first { $0.pid == pid }?.args
    }
}

/// Process start times as `ps -o lstart=` prints them ("Mon Oct 19 09:12:03 2026", local time),
/// the format of the state files' `procStart`.
public enum ProcStart {
    private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }

    /// Epoch seconds for an lstart string; runs of spaces are allowed. Nil when it doesn't parse.
    public static func parse(_ text: String, timeZone: TimeZone = .current) -> Int64? {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return formatter(timeZone).date(from: normalized).map { Int64($0.timeIntervalSince1970) }
    }

    /// The lstart string for epoch seconds, with the day padded to two characters like `ps` does
    /// ("Mon Oct  5 09:12:03 2026").
    public static func format(_ seconds: Int64, timeZone: TimeZone = .current) -> String {
        let parts = formatter(timeZone).string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
            .split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 5 else { return parts.joined(separator: " ") }
        let day = parts[2].count == 1 ? " \(parts[2])" : String(parts[2])
        return "\(parts[0]) \(parts[1]) \(day) \(parts[3]) \(parts[4])"
    }

    /// Whether an lstart string names the same start time as `seconds`.
    public static func matches(_ text: String, seconds: Int64, timeZone: TimeZone = .current) -> Bool {
        parse(text, timeZone: timeZone) == seconds
    }
}
