import Foundation

/// `asb install` and `asb uninstall`: the hooks in Claude Code's settings and a copy of asb at a stable
/// path for them to run. Install also cleans up after the SwiftBar plugin this project used to be.
/// Everything it touches is a parameter, so tests run it in a temporary home.
public struct Installer {
    public var settingsFile: String
    /// Where the hooks run asb from: stays put when the repo or a download moves.
    public var stableBinary: String
    /// The asb being run, copied to `stableBinary`.
    public var sourceBinary: String
    /// SwiftBar's plugin folder, when known: an old link to our plugin there is removed.
    public var swiftBarDir: String?
    public var loginItemFile: String
    public var stateDir: String
    public var configFile: String
    public var now: Date = Date()
    /// Progress messages for the user.
    public var log: (String) -> Void = { print($0) }
    /// Where the SwiftBar plugin kept things before the rename to agentic-status-bar; install moves them.
    public var old: OldPaths?

    public struct OldPaths {
        public var stateDir: String
        public var configFile: String
        public var loginItemFile: String

        public init(stateDir: String, configFile: String, loginItemFile: String) {
            self.stateDir = stateDir
            self.configFile = configFile
            self.loginItemFile = loginItemFile
        }
    }

    public static let pluginName = "agentic-status-bar.5s.sh"
    public static let oldPluginName = "swiftbar-claudecode-minimal.5s.sh"

    public init(
        settingsFile: String, stableBinary: String, sourceBinary: String, swiftBarDir: String?,
        loginItemFile: String, stateDir: String, configFile: String
    ) {
        self.settingsFile = settingsFile
        self.stableBinary = stableBinary
        self.sourceBinary = sourceBinary
        self.swiftBarDir = swiftBarDir
        self.loginItemFile = loginItemFile
        self.stateDir = stateDir
        self.configFile = configFile
    }

    public enum Failure: Error, Equatable {
        case invalidSettings(String)
        case cannotWrite(String)
    }

    private var fm: FileManager { FileManager.default }

    // MARK: Install

    public func install() throws {
        try copyBinary()
        var settings = try readSettings(backup: true) ?? .object([])
        settings = HookSettings.install(settings, command: HookSettings.command(asb: stableBinary))
        try writeSettings(settings)
        log("Hooks registered in \(settingsFile)")
        migrate()
        removeSwiftBarPlugin()
        log("Done. New Claude Code sessions will show up in the menu bar.")
    }

    /// Moves the config, state files and mutes from the old paths. Anything already at the new path
    /// wins; nothing is overwritten.
    func migrate() {
        guard let old else { return }
        if fm.fileExists(atPath: old.configFile), !fm.fileExists(atPath: configFile) {
            try? fm.createDirectory(atPath: (configFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if (try? fm.moveItem(atPath: old.configFile, toPath: configFile)) != nil { log("Moved \(old.configFile) to \(configFile)") }
            removeIfEmpty((old.configFile as NSString).deletingLastPathComponent)
        }
        if let names = try? fm.contentsOfDirectory(atPath: old.stateDir) {
            try? fm.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            for name in names where name.hasSuffix(".json") || name == Mutes.fileName || name == "plugin.log" {
                let from = (old.stateDir as NSString).appendingPathComponent(name)
                let to = (stateDir as NSString).appendingPathComponent(name)
                if !fm.fileExists(atPath: to) { try? fm.moveItem(atPath: from, toPath: to) }
            }
            log("Moved state files from \(old.stateDir) to \(stateDir)")
        }
    }

    /// The SwiftBar plugin is gone: removes our links in SwiftBar's plugin folder and the login items
    /// that started SwiftBar (the app is its own login item, in its Settings).
    func removeSwiftBarPlugin() {
        for item in [old?.loginItemFile, loginItemFile].compactMap({ $0 }) where fm.fileExists(atPath: item) {
            try? fm.removeItem(atPath: item)
            log("Removed the SwiftBar login item \(item)")
        }
        removeOurLink(named: Self.pluginName)
        removeOurLink(named: Self.oldPluginName)
    }

    /// Removes a SwiftBar link of ours: one pointing at a plugin file of this project.
    func removeOurLink(named name: String) {
        guard let dir = swiftBarDir, !dir.isEmpty else { return }
        let link = (dir as NSString).appendingPathComponent(name)
        guard let target = try? fm.destinationOfSymbolicLink(atPath: link),
              target.hasSuffix("/swiftbar/\(Self.pluginName)") || target.hasSuffix("/swiftbar/\(Self.oldPluginName)")
        else { return }
        try? fm.removeItem(atPath: link)
        log("Removed \(link)")
    }

    /// Whether the settings have our hook for every event (an unreadable file counts as no).
    public var hooksInstalled: Bool {
        guard let settings = try? readSettings(backup: false) else { return false }
        return HookSettings.count(settings) >= HookSettings.events.count
    }

    /// Whether the stable copy is byte for byte the asb being run.
    public var binaryIsCurrent: Bool {
        guard let stable = fm.contents(atPath: stableBinary) else { return false }
        return fm.contents(atPath: sourceBinary) == stable
    }

    /// Replaces the stable copy with the asb being run, leaving the settings alone.
    public func updateBinary() throws {
        try copyBinary()
    }

    func copyBinary() throws {
        let source = URL(fileURLWithPath: sourceBinary).resolvingSymlinksInPath().path
        guard source != URL(fileURLWithPath: stableBinary).resolvingSymlinksInPath().path else { return }
        let dir = (stableBinary as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let tmp = "\(stableBinary).tmp.\(getpid())"
        try? fm.removeItem(atPath: tmp)
        try fm.copyItem(atPath: source, toPath: tmp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp)
        guard rename(tmp, stableBinary) == 0 else {
            try? fm.removeItem(atPath: tmp)
            throw Failure.cannotWrite(stableBinary)
        }
        log("Installed asb at \(stableBinary)")
    }

    /// The settings, or nil when the file doesn't exist. A file that isn't a JSON object is never changed.
    func readSettings(backup: Bool) throws -> OrderedJSON? {
        guard let data = fm.contents(atPath: settingsFile) else { return nil }
        guard let settings = try? OrderedJSON.parse(data), settings.isObject else {
            throw Failure.invalidSettings(settingsFile)
        }
        if backup {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let copy = "\(settingsFile).bak-agentic-status-bar-\(f.string(from: now))"
            try? fm.removeItem(atPath: copy)
            try fm.copyItem(atPath: settingsFile, toPath: copy)
            log("Backed up \(settingsFile) to \(copy)")
        }
        return settings
    }

    func writeSettings(_ settings: OrderedJSON) throws {
        try fm.createDirectory(atPath: (settingsFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard StateWriter.atomicWrite(Data(settings.serialized().utf8), to: settingsFile) else {
            throw Failure.cannotWrite(settingsFile)
        }
    }

    // MARK: Uninstall

    /// Removes our hooks, SwiftBar-era leftovers and the stable asb. State and config go too when
    /// `purge` is set or `confirmPurge` says yes.
    public func uninstall(purge: Bool, confirmPurge: () -> Bool = { false }) throws {
        if let settings = try readSettings(backup: true) {
            try writeSettings(HookSettings.uninstall(settings))
            log("Removed the hooks from \(settingsFile)")
        }
        removeSwiftBarPlugin()
        if fm.fileExists(atPath: stableBinary) {
            try? fm.removeItem(atPath: stableBinary)
            removeIfEmpty((stableBinary as NSString).deletingLastPathComponent)
            removeIfEmpty(((stableBinary as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent)
            log("Removed \(stableBinary)")
        }
        if purge || confirmPurge() {
            try? fm.removeItem(atPath: stateDir)
            try? fm.removeItem(atPath: configFile)
            removeIfEmpty((configFile as NSString).deletingLastPathComponent)
            log("Deleted \(stateDir) and \(configFile)")
        }
        log("Done.")
    }

    func removeIfEmpty(_ dir: String) {
        if (try? fm.contentsOfDirectory(atPath: dir))?.isEmpty == true { try? fm.removeItem(atPath: dir) }
    }
}
