import Foundation

/// Runs external commands for the menu actions (open, pbcopy, herdr). Injectable so tests can record calls.
public protocol CommandRunner {
    /// Runs `command` (a name looked up on PATH, or a path) and reports whether it exited with 0.
    /// Gives up after `timeout` seconds when one is given.
    @discardableResult
    func run(_ command: String, _ arguments: [String], input: Data?, timeout: TimeInterval?) -> Bool
}

/// Runs commands with Foundation's Process.
public struct ProcessRunner: CommandRunner {
    public var environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// The path of `command`: as given when it contains a slash, else the first match on PATH.
    public func resolve(_ command: String) -> String? {
        if command.contains("/") { return command }
        let dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/usr/bin", "/bin"]
        return dirs.map { "\($0)/\(command)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    public func run(_ command: String, _ arguments: [String], input: Data?, timeout: TimeInterval?) -> Bool {
        guard let path = resolve(command) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = input.map { _ in Pipe() }
        process.standardInput = pipe ?? FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        guard (try? process.run()) != nil else { return false }
        if let pipe, let input {
            pipe.fileHandleForWriting.write(input)
            try? pipe.fileHandleForWriting.close()
        }
        if let timeout, done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return false
        }
        if timeout == nil { done.wait() }
        return process.terminationStatus == 0
    }
}

/// The menu actions. They never fail loudly: anything invalid or missing does nothing.
public struct Actions {
    public var paths: Paths
    public var environment: [String: String]
    public var runner: CommandRunner
    public var now: () -> Int64
    public var timeZone: TimeZone
    /// Seconds each focus step may take before it is abandoned.
    public var focusTimeout: TimeInterval = 2

    public init(
        paths: Paths, environment: [String: String], runner: CommandRunner,
        now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }, timeZone: TimeZone = .current
    ) {
        self.paths = paths
        self.environment = environment
        self.runner = runner
        self.now = now
        self.timeZone = timeZone
    }

    /// The config keys the menu's checkmark items toggle.
    public static let toggleKeys: Set = [
        "show_interactive", "show_headless", "show_subagents", "show_ide", "use_registry", "store_prompt_preview",
    ]
    /// The only values `set` accepts: the menu's choices.
    public static let settable: [String: Set<String>] = [
        "stale_minutes": ["0", "10", "30", "60"],
        "theme": ["default", "monochrome", "high_contrast"],
    ]

    public func perform(_ name: String, _ args: [String]) {
        let first = args.first ?? ""
        switch name {
        case "focus": focus(first)
        case "toggle": toggle(first)
        case "set": if args.count >= 2 { set(first, args[1]) }
        case "reveal-config": revealConfig()
        case "mute-hour": muteProject(first) { Mutes.muteHour(&$0, cwd: $1, now: now()) }
        case "mute-today": muteProject(first) { Mutes.muteToday(&$0, cwd: $1, now: now(), timeZone: timeZone) }
        case "unmute": muteProject(first) { $0[$1] = nil }
        case "unmute-all": updateMutes { $0 = [:] }
        case "copy-id": copy(field(first) { $0.sessionId })
        case "copy-cwd": copy(field(first) { $0.cwd })
        case "open-folder":
            var isDir: ObjCBool = false
            if let dir = field(first, { $0.cwd }), FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
                runner.run("open", [dir], input: nil, timeout: nil)
            }
        case "reveal-transcript":
            if let path = field(first, { $0.transcriptPath }), FileManager.default.fileExists(atPath: path) {
                runner.run("open", ["-R", path], input: nil, timeout: nil)
            }
        default: break
        }
    }

    // MARK: Pieces

    var config: Config { Config.load(paths) }
    var stateDir: String { paths.stateDir(config: config) }

    /// Session IDs become file names: only safe characters.
    public static func isSafeId(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-")
        }
    }

    /// A field of the session's state file, or nil (unsafe ID, no file, no such field, empty).
    func field(_ id: String, _ pick: (StateFile) -> String?) -> String? {
        guard Self.isSafeId(id) else { return nil }
        let path = (stateDir as NSString).appendingPathComponent("\(id).json")
        guard let data = FileManager.default.contents(atPath: path),
              let file = StateFile.parse(RawFile(path: path, contents: data)),
              let value = pick(file), !value.isEmpty
        else { return nil }
        return value
    }

    func copy(_ value: String?) {
        guard let value else { return }
        runner.run("pbcopy", [], input: Data(value.utf8), timeout: nil)
    }

    /// Brings the session's herdr pane to the front, then raises the terminal hosting herdr. Fails
    /// safe: on any error nothing else happens; it never launches apps or opens windows.
    func focus(_ id: String) {
        guard let pane = field(id, { $0.herdrPane }), Self.onlyContains(pane, extra: ":_-"),
              let herdr = Herdr.find(environment: environment),
              runner.run(herdr, ["agent", "focus", pane], input: nil, timeout: focusTimeout)
        else { return }
        guard let bundle = field(id, { $0.termBundleId }), Self.onlyContains(bundle, extra: ".-") else { return }
        runner.run("open", ["-b", bundle], input: nil, timeout: focusTimeout)
    }

    static func onlyContains(_ text: String, extra: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || extra.unicodeScalars.contains($0)) }
    }

    func toggle(_ key: String) {
        guard Self.toggleKeys.contains(key) else { return }
        let c = config
        let on: Bool = switch key {
        case "show_interactive": c.showInteractive
        case "show_headless": c.showHeadless
        case "show_subagents": c.showSubagents
        case "show_ide": c.showIDE
        case "use_registry": c.useRegistry
        default: c.storePromptPreview
        }
        _ = try? Config.set(key, on ? "0" : "1", in: paths.configFile)
    }

    func set(_ key: String, _ value: String) {
        guard Self.settable[key]?.contains(value) == true else { return }
        _ = try? Config.set(key, value, in: paths.configFile)
    }

    func revealConfig() {
        let file = paths.configFile
        if !FileManager.default.fileExists(atPath: file) {
            try? FileManager.default.createDirectory(
                atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? Self.defaultConfig(config).write(toFile: file, atomically: true, encoding: .utf8)
        }
        runner.run("open", ["-R", file], input: nil, timeout: nil)
    }

    /// A config file with every key at its current value, and how to override the theme.
    public static func defaultConfig(_ c: Config) -> String {
        func flag(_ on: Bool) -> String { on ? "1" : "0" }
        var text = """
            # Agentic Status Bar settings (key=value). The app's Settings edit this file too.
            show_interactive=\(flag(c.showInteractive))
            show_headless=\(flag(c.showHeadless))
            show_subagents=\(flag(c.showSubagents))
            show_ide=\(flag(c.showIDE))
            stale_minutes=\(c.staleMinutes)
            use_registry=\(flag(c.useRegistry))
            store_prompt_preview=\(flag(c.storePromptPreview))

            # App notifications: waiting on you, idle, after how many seconds, with a sound.
            notify_waiting=\(flag(c.notifyWaiting))
            notify_idle=\(flag(c.notifyIdle))
            notify_delay_seconds=\(c.notifyDelaySeconds)
            notify_sound=\(flag(c.notifySound))

            # Theme: default, monochrome or high_contrast.
            theme=\(c.theme)
            # Override the theme for one state (waiting, idle, uncertain, busy, subagents,
            # muted, none, warning) with an SF Symbol name and a #RRGGBB color or a light,dark pair, e.g.
            #   icon_idle=moon.zzz
            #   color_idle=#B25000,#FFD60A

            """
        for state in Config.themeStates {
            if let icon = c.iconOverrides[state] { text += "icon_\(state)=\(icon)\n" }
            if let color = c.colorOverrides[state] { text += "color_\(state)=\(color)\n" }
        }
        if !c.icon.isEmpty { text += "icon=\(c.icon)\n" }
        return text
    }

    func updateMutes(_ change: (inout [String: Mute]) -> Void) {
        let file = (stateDir as NSString).appendingPathComponent(Mutes.fileName)
        try? Mutes.update(file: file, now: now(), change: change)
    }

    func muteProject(_ id: String, _ change: (inout [String: Mute], String) -> Void) {
        guard let cwd = field(id, { $0.cwd }) else { return }
        updateMutes { change(&$0, cwd) }
    }
}
