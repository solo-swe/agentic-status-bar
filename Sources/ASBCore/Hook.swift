import Foundation

/// What `asb hook` does: records one Claude Code hook event in the session's state file
/// (`doc/state-file-schema.md` › Writer rules, `doc/guides/hook.md`). It never fails and never prints:
/// bad input is dropped.
public enum Hook {
    /// The current time in epoch milliseconds: the hook's clock.
    public static func epochMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Handles one hook call: appends the payload to the debug log when the config turns it on, then,
    /// for a valid payload with a safe session ID, applies the event to `<state dir>/<session ID>.json`
    /// under the session's lock (`HookEvents.apply`), backfills the session details when they are missing,
    /// and writes or deletes the file atomically. At `SessionStart` it also removes the state files left
    /// for the same claude process by its earlier session.
    ///
    /// - Parameters:
    ///   - input: The payload, as Claude Code writes it to the hook's standard input.
    ///   - started: When the hook started (epoch ms), taken before reading `input`: async hooks finish
    ///     out of order, and an event that started earlier must not overwrite a later one.
    ///   - environment: The hook's environment: `HOME` and the `ASB_*` overrides (`Paths`), and the
    ///     variables `HookMetadata.gather` reads.
    ///   - parentPid: The hook's parent process, where the walk up to the claude process starts.
    ///   - inspector: The process table, read only when an event needs the session details.
    ///   - now: The clock for the write (`updatedAt`), read while holding the lock.
    ///
    /// ```swift
    /// let started = Hook.epochMilliseconds()
    /// let input = FileHandle.standardInput.readDataToEndOfFile()
    /// let environment = ProcessInfo.processInfo.environment
    /// Hook.handle(input, started: started, environment: environment, parentPid: getppid(),
    ///             inspector: ProcessInspectors.fromEnvironment(environment))
    /// ```
    public static func handle(
        _ input: Data, started: Int64, environment: [String: String], parentPid: Int32,
        inspector: any ProcessInspector, now: () -> Int64 = epochMilliseconds
    ) {
        let paths = Paths.from(environment: environment)
        let config = Config.load(paths)
        let stateDir = paths.stateDir(config: config)

        // Debugging: keep every payload as received, also the ones this hook ignores.
        if config.debugHookLog {
            try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            HookLog.append(
                HookLog.line(payload: input, environment: environment, parentPid: parentPid, now: started),
                stateDir: stateDir)
        }

        guard let payload = HookPayload.parse(input), !payload.event.isEmpty,
              Actions.isSafeId(payload.sessionId)
        else { return }

        let file = (stateDir as NSString).appendingPathComponent("\(payload.sessionId).json")
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let metadata = MetadataLookup {
            HookMetadata.gather(environment: environment, parentPid: parentPid, inspector: inspector)
        }

        StateWriter.withLock(file) {
            let outcome = outcome(
                of: payload, current: readState(file), now: now(), started: started,
                storePromptPreview: config.storePromptPreview, metadata: metadata)
            write(outcome, to: file)
        }

        if payload.event == "SessionStart", let pid = metadata.found?.pid {
            removeStaleFiles(of: pid, in: stateDir, keeping: file)
        }
    }

    /// The state file's object, or nil when it is missing or corrupt.
    static func readState(_ file: String) -> [String: Any]? {
        FileManager.default.contents(atPath: file)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// The event applied to the current state, with the session details backfilled for sessions that
    /// were running before the hooks were installed.
    static func outcome(
        of payload: HookPayload, current: [String: Any]?, now: Int64, started: Int64,
        storePromptPreview: Bool, metadata: MetadataLookup
    ) -> HookEvents.Outcome {
        let outcome = HookEvents.apply(
            payload, to: current, now: now, started: started, storePromptPreview: storePromptPreview,
            sessionStartChanges: { metadata.value.apply(to: &$0, cwd: payload.cwd, transcriptPath: payload.transcriptPath) })
        guard case .write(let state) = outcome, payload.event != "SessionStart", !payload.cwd.isEmpty,
              HookMetadata.needsBackfill(state, event: payload.event)
        else { return outcome }
        var filled: [String: Any] = state
        metadata.value.apply(to: &filled, cwd: payload.cwd, transcriptPath: payload.transcriptPath)
        return .write(HookEvents.hashable(filled))
    }

    static func write(_ outcome: HookEvents.Outcome, to file: String) {
        switch outcome {
        case .write(let state):
            var data = HookEvents.encode(state)
            data.append(UInt8(ascii: "\n"))
            StateWriter.atomicWrite(data, to: file)
        case .delete:
            try? FileManager.default.removeItem(atPath: file)
        case .none:
            break
        }
    }

    /// Files left for this process belong to its earlier session (e.g. before a /clear). The app
    /// watches the state dir, so removing them is all it takes to update the menu bar.
    static func removeStaleFiles(of pid: Int32, in stateDir: String, keeping file: String) {
        for stale in HookMetadata.staleFiles(for: pid, in: StateDirectory.read(stateDir), own: file) {
            try? FileManager.default.removeItem(atPath: stale)
        }
    }
}

/// The session details, looked up at most once and only when an event needs them: walking the
/// process table costs time on every tool call.
final class MetadataLookup {
    private let gather: () -> HookMetadata
    /// The details, once looked up.
    private(set) var found: HookMetadata?

    init(_ gather: @escaping () -> HookMetadata) {
        self.gather = gather
    }

    var value: HookMetadata {
        if let found { return found }
        let gathered = gather()
        found = gathered
        return gathered
    }
}
