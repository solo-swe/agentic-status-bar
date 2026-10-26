import Foundation

/// Writing state files safely while several async hooks of one session may run at once
/// (doc/state-file-schema.md › Writer rules).
public enum StateWriter {
    /// Runs `body` holding the per-session lock `<file>.lock` (a directory: mkdir is atomic). Retries
    /// `tries` times every `interval` seconds, then gives up quietly and returns false.
    @discardableResult
    public static func withLock(_ file: String, tries: Int = 50, interval: TimeInterval = 0.01, _ body: () -> Void) -> Bool {
        let lock = file + ".lock"
        var acquired = false
        for attempt in 0..<tries {
            if mkdir(lock, 0o755) == 0 {
                acquired = true
                break
            }
            if attempt < tries - 1 { Thread.sleep(forTimeInterval: interval) }
        }
        guard acquired else { return false }
        defer { rmdir(lock) }
        body()
        return true
    }

    /// Writes `data` to `<file>.tmp.<pid>`, then renames it over `file`, so readers never see half a file.
    @discardableResult
    public static func atomicWrite(_ data: Data, to file: String) -> Bool {
        let tmp = "\(file).tmp.\(getpid())"
        guard FileManager.default.createFile(atPath: tmp, contents: data) else { return false }
        guard rename(tmp, file) == 0 else {
            unlink(tmp)
            return false
        }
        return true
    }
}
