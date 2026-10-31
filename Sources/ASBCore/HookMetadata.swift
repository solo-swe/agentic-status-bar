import Foundation

/// Session details the hook records at SessionStart, or backfills once for sessions that were
/// already running when the hooks were installed (doc/state-file-schema.md › Metadata).
public struct HookMetadata: Equatable, Sendable {
    /// The claude process; nil when none was found (recorded as `pid: null`, so the lookup isn't repeated).
    public var pid: Int32?
    /// Its start time as `ps -o lstart=` prints it.
    public var procStart: String?
    public var kind: String
    public var herdrPane: String?
    public var termBundleId: String?

    /// How many parent levels the walk to the claude process goes up.
    public static let maxDepth = 6

    /// Gathers the details from the environment and the process table. The walk starts at
    /// `ASB_PARENT_PID` (tests) or the hook's parent.
    public static func gather(
        environment: [String: String], parentPid: Int32, inspector: any ProcessInspector,
        timeZone: TimeZone = .current
    ) -> HookMetadata {
        let start = environment["ASB_PARENT_PID"].flatMap { Int32($0) } ?? parentPid
        let pid = findClaude(from: start, inspector: inspector)
        let process = pid.flatMap { inspector.process($0) }
        func nonEmpty(_ key: String) -> String? {
            guard let value = environment[key], !value.isEmpty else { return nil }
            return value
        }
        return HookMetadata(
            pid: pid,
            procStart: process.map { ProcStart.format($0.start, timeZone: timeZone) },
            kind: kind(entrypoint: environment["CLAUDE_CODE_ENTRYPOINT"] ?? "", arguments: pid.flatMap { inspector.arguments($0) }),
            herdrPane: nonEmpty("HERDR_PANE_ID"),
            termBundleId: nonEmpty("__CFBundleIdentifier"))
    }

    /// Walks up from `start` to the first `claude` process (or `node` running claude, as npm installs do).
    /// The native install runs `~/.local/share/claude/versions/<version>` through a `claude` symlink, so
    /// its process is named after the version; its argv[0] is still `claude`.
    public static func findClaude(from start: Int32, inspector: any ProcessInspector) -> Int32? {
        var pid = start
        for _ in 0..<maxDepth {
            guard pid > 1, let process = inspector.process(pid) else { return nil }
            let name = (process.comm as NSString).lastPathComponent
            switch name {
            case "claude": return pid
            case "node" where inspector.arguments(pid)?.contains("claude") == true: return pid
            case _ where isVersion(name) && argv0(inspector.arguments(pid)) == "claude": return pid
            default: pid = process.ppid
            }
        }
        return nil
    }

    /// `2.1.316`: digits and dots, starting with a digit.
    static func isVersion(_ name: String) -> Bool {
        name.first?.isNumber == true && name.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// The last path component of a command line's first word.
    static func argv0(_ arguments: String?) -> String? {
        arguments?.split(separator: " ").first.map { (String($0) as NSString).lastPathComponent }
    }

    /// interactive, headless, ide or desktop.
    public static func kind(entrypoint: String, arguments: String?) -> String {
        if entrypoint.hasPrefix("sdk-") { return "headless" }
        if ["vscode", "jetbrains", "ide"].contains(where: entrypoint.contains) { return "ide" }
        if entrypoint.contains("desktop") { return "desktop" }
        if let args = arguments, " \(args) ".contains(" -p ") || " \(args) ".contains(" --print ") { return "headless" }
        return "interactive"
    }

    /// Records the details in a state object, with the payload's cwd and transcript path.
    public func apply(to state: inout [String: Any], cwd: String, transcriptPath: String) {
        state["cwd"] = cwd
        state["transcriptPath"] = transcriptPath
        state["kind"] = kind
        if let pid {
            state["pid"] = Int(pid)
            state["procStart"] = procStart
        } else {
            state["pid"] = NSNull()
            state["procStart"] = nil
        }
        state["herdrPane"] = herdrPane
        state["termBundleId"] = termBundleId
    }

    /// Whether a written state still lacks the details (the session predates the hooks).
    /// A `pid` of null counts as recorded.
    /// A null `pid` is looked up again on each prompt: older versions missed the native install's process.
    public static func needsBackfill(_ state: [String: Any], event: String = "") -> Bool {
        state["pid"] == nil || state["cwd"] == nil || (event == "UserPromptSubmit" && state["pid"] is NSNull)
    }

    /// State files in `files` (other than `own`) recorded for `pid`: a claude process runs one session
    /// at a time, so they belong to an earlier session (e.g. before a /clear).
    public static func staleFiles(for pid: Int32, in files: [RawFile], own: String) -> [String] {
        files.filter { $0.path != own }.compactMap { file in
            StateFile.parse(file)?.pid == pid ? file.path : nil
        }
    }
}
