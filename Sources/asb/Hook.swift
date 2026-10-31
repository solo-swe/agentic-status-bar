import ArgumentParser
import ASBCore
import Foundation

/// The Claude Code hook: turns hook events into one state file per session. It must never get in
/// Claude Code's way: it prints nothing and always exits 0.
struct HookCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hook",
        abstract: "Record a Claude Code hook event (payload on stdin) in the session's state file."
    )

    func run() {
        // When the event started: async hooks finish out of order, and an older event must not
        // overwrite a newer one.
        let started = Int64(Date().timeIntervalSince1970 * 1000)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let environment = ProcessInfo.processInfo.environment
        let paths = Paths.from(environment: environment)
        let config = Config.load(paths)
        let stateDir = paths.stateDir(config: config)

        // Debugging: keep every payload as received, also the ones this hook ignores.
        if config.debugHookLog {
            try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            HookLog.append(
                HookLog.line(payload: input, environment: environment, parentPid: getppid(), now: started),
                stateDir: stateDir)
        }

        guard let payload = HookPayload.parse(input), !payload.event.isEmpty,
              Actions.isSafeId(payload.sessionId)
        else { return }

        let file = (stateDir as NSString).appendingPathComponent("\(payload.sessionId).json")
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        // Looked up only when needed: walking the process table costs time on every tool call.
        var metadata: HookMetadata?
        func details() -> HookMetadata {
            if let metadata { return metadata }
            let found = HookMetadata.gather(
                environment: environment, parentPid: getppid(), inspector: ProcessInspectors.fromEnvironment(environment))
            metadata = found
            return found
        }

        StateWriter.withLock(file) {
            let current = FileManager.default.contents(atPath: file)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            var outcome = HookEvents.apply(
                payload, to: current, now: now, started: started, storePromptPreview: config.storePromptPreview,
                sessionStartChanges: { details().apply(to: &$0, cwd: payload.cwd, transcriptPath: payload.transcriptPath) })

            // Backfill sessions that were running before the hooks were installed.
            if case .write(let state) = outcome, payload.event != "SessionStart", !payload.cwd.isEmpty,
               HookMetadata.needsBackfill(state, event: payload.event) {
                var filled: [String: Any] = state
                details().apply(to: &filled, cwd: payload.cwd, transcriptPath: payload.transcriptPath)
                outcome = .write(HookEvents.hashable(filled))
            }

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

        // The app watches the state dir, so a write is all it takes to update the menu bar.
        if payload.event == "SessionStart", let pid = metadata?.pid {
            for stale in HookMetadata.staleFiles(for: pid, in: StateDirectory.read(stateDir), own: file) {
                try? FileManager.default.removeItem(atPath: stale)
            }
        }
    }
}
