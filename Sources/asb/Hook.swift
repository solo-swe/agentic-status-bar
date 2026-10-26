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
        let started = Int64(Date().timeIntervalSince1970 * 1000)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = HookPayload.parse(input), !payload.event.isEmpty,
              Actions.isSafeId(payload.sessionId)
        else { return }

        let environment = ProcessInfo.processInfo.environment
        let paths = Paths.from(environment: environment)
        let config = Config.load(paths)
        let stateDir = paths.stateDir(config: config)
        let file = (stateDir as NSString).appendingPathComponent("\(payload.sessionId).json")

        let current = FileManager.default.contents(atPath: file)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        switch HookEvents.apply(payload, to: current, now: now, started: started,
                                storePromptPreview: config.storePromptPreview) {
        case .write(let state):
            try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            var data = HookEvents.encode(state)
            data.append(UInt8(ascii: "\n"))
            try? data.write(to: URL(fileURLWithPath: file), options: .atomic)
        case .delete:
            try? FileManager.default.removeItem(atPath: file)
        case .none:
            break
        }
    }
}
