import Foundation

/// Gathers `SnapshotInputs` from disk and the system, and carries out a snapshot's side effects.
public struct LiveInputs {
    public var paths: Paths
    public var environment: [String: String]
    public var inspector: any ProcessInspector
    /// Seconds `herdr agent list` may take before titles are skipped for this snapshot.
    public var herdrTimeout: TimeInterval = 1

    public init(paths: Paths, environment: [String: String], inspector: any ProcessInspector) {
        self.paths = paths
        self.environment = environment
        self.inspector = inspector
    }

    public func gather(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000), timeZone: TimeZone = .current) -> SnapshotInputs {
        let configText = try? String(contentsOfFile: paths.configFile, encoding: .utf8)
        let config = Config.parse(configText)
        let stateDir = paths.stateDir(config: config)
        let stateFiles = StateDirectory.read(stateDir)

        var inputs = SnapshotInputs(now: now, timeZone: timeZone, stateFiles: stateFiles, configText: configText)
        if config.useRegistry {
            inputs.registryFiles = StateDirectory.read(paths.registryDir)
        }
        // Transcripts only of sessions whose file says busy or waiting (checks C3 and C5).
        for state in ParsedStates.parse(stateFiles).sessions where Checks.readsTranscript(state) {
            guard let path = state.transcriptPath, inputs.transcripts[path] == nil,
                  let transcript = Self.readTail(path) else { continue }
            inputs.transcripts[path] = transcript
        }
        inputs.processes = inspector.processes()
        if let herdr = Herdr.find(environment: environment) {
            inputs.herdrInstalled = true
            inputs.herdrList = Herdr.run(herdr, ["agent", "list"], timeout: herdrTimeout)
        }
        inputs.mutesText = try? String(contentsOfFile: (stateDir as NSString).appendingPathComponent(Mutes.fileName), encoding: .utf8)
        return inputs
    }

    /// The end of a transcript and its modification time. One byte more than the engine reads is
    /// kept when the file is longer, so the engine knows the first line was cut.
    static func readTail(_ path: String) -> TranscriptInput? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let keep = UInt64(Transcript.tailBytes + 1)
        try? handle.seek(toOffset: size > keep ? size - keep : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
        return TranscriptInput(mtime: modified.map { Int64($0.timeIntervalSince1970) * 1000 } ?? 0, contents: data)
    }

    /// Deletes the state files of dead sessions (only `*.json` files in the state dir) and logs a
    /// registry format change once.
    public func apply(_ result: SnapshotResult, configText: String?) {
        let stateDir = paths.stateDir(config: Config.parse(configText))
        for file in result.deadFiles
        where (file as NSString).deletingLastPathComponent == stateDir && file.hasSuffix(".json") {
            try? FileManager.default.removeItem(atPath: file)
        }
        if result.registrySchemaIssue {
            PluginLog.once(stateDir: stateDir, key: "registry-schema",
                message: "Claude Code session registry has no 'status' field; registry override disabled for those sessions.")
        }
    }
}

/// Messages for troubleshooting in `<state dir>/plugin.log`, each kind written once.
public enum PluginLog {
    public static func once(stateDir: String, key: String, message: String, now: Date = Date()) {
        let path = (stateDir as NSString).appendingPathComponent("plugin.log")
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard !existing.split(separator: "\n").contains(where: { $0.hasPrefix("[\(key)] ") }) else { return }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        let line = "[\(key)] \(f.string(from: now)) \(message)\n"
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
        }
    }
}

/// The herdr terminal multiplexer's CLI, used for pane titles and focusing.
public enum Herdr {
    /// herdr's path. `ASB_HERDR`, when set, is the only candidate (used by tests).
    public static func find(environment: [String: String]) -> String? {
        let fm = FileManager.default
        if let only = environment["ASB_HERDR"] {
            return fm.isExecutableFile(atPath: only) ? only : nil
        }
        let path = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/herdr" }
        return (["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"] + path).first { fm.isExecutableFile(atPath: $0) }
    }

    /// Runs herdr and returns its output, or nil if it fails or takes longer than `timeout`. Output goes
    /// to a temp file, not a pipe: a child herdr leaves behind can't hold the snapshot up.
    public static func run(_ herdr: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("asb-herdr-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: out.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: out) else { return nil }
        defer { try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: herdr)
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { try? handle.close(); return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            try? handle.close()
            return nil
        }
        try? handle.close()
        guard process.terminationStatus == 0 else { return nil }
        return try? String(contentsOf: out, encoding: .utf8)
    }
}
