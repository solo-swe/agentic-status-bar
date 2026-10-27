import Foundation

/// A debugging log of the raw payloads `asb hook` receives, written while the config has `debug_hook_log=1`.
/// One JSON object per line: when the hook ran, its parent process, the environment variables the hook
/// reads, and the payload as Claude Code sent it.
public enum HookLog {
    public static let fileName = "hook-payloads.jsonl"
    /// Past this size nothing more is appended, so a forgotten switch can't fill the disk.
    public static let maxBytes = 5_000_000
    /// The environment variables `HookMetadata` reads.
    public static let environmentKeys = ["CLAUDE_CODE_ENTRYPOINT", "HERDR_PANE_ID", "__CFBundleIdentifier"]

    /// The log line for one hook call; a payload that isn't JSON is kept as a string.
    public static func line(payload: Data, environment: [String: String], parentPid: Int32, now: Int64) -> Data {
        let parsed = (try? JSONSerialization.jsonObject(with: payload)) ?? String(decoding: payload, as: UTF8.self)
        let entry: [String: Any] = [
            "at": now,
            "ppid": Int(parentPid),
            "env": environment.filter { environmentKeys.contains($0.key) },
            "payload": parsed,
        ]
        var data = (try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Appends `line` to the log in `stateDir`, unless the log is already `maxBytes` or more. One `write` on
    /// a file opened for appending, so lines from hooks running at the same time don't interleave.
    public static func append(_ line: Data, stateDir: String, maxBytes: Int = maxBytes) {
        let file = (stateDir as NSString).appendingPathComponent(fileName)
        let size = (try? FileManager.default.attributesOfItem(atPath: file)[.size] as? Int) ?? 0
        guard size < maxBytes else { return }
        let fd = open(file, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}
