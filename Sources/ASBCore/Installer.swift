import Foundation

/// `asb install` and `asb uninstall`: the hooks in Claude Code's settings, a copy of asb at a stable
/// path for them to run, and the SwiftBar plugin link. Everything it touches is a parameter, so tests
/// run it in a temporary home.
public struct Installer {
    public var settingsFile: String
    /// Where the hooks run asb from: stays put when the repo or a download moves.
    public var stableBinary: String
    /// The asb being run, copied to `stableBinary`.
    public var sourceBinary: String
    /// The SwiftBar plugin file to link, when one is known.
    public var pluginFile: String?
    /// SwiftBar's plugin folder, when known.
    public var swiftBarDir: String?
    public var loginItemFile: String
    public var stateDir: String
    public var configFile: String
    public var now: Date = Date()
    /// Progress messages for the user.
    public var log: (String) -> Void = { print($0) }

    public static let pluginName = "swiftbar-claudecode-minimal.5s.sh"

    public init(
        settingsFile: String, stableBinary: String, sourceBinary: String, pluginFile: String?, swiftBarDir: String?,
        loginItemFile: String, stateDir: String, configFile: String
    ) {
        self.settingsFile = settingsFile
        self.stableBinary = stableBinary
        self.sourceBinary = sourceBinary
        self.pluginFile = pluginFile
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
        linkPlugin()
        log("Done. New Claude Code sessions will show up in the menu bar.")
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

    func linkPlugin() {
        guard let pluginFile, let dir = swiftBarDir, !dir.isEmpty else {
            log("Skipped the SwiftBar link: SwiftBar has no plugin folder yet.")
            return
        }
        let link = (dir as NSString).appendingPathComponent(Self.pluginName)
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if (try? fm.destinationOfSymbolicLink(atPath: link)) != nil { try fm.removeItem(atPath: link) }
            try fm.createSymbolicLink(atPath: link, withDestinationPath: pluginFile)
            log("Linked \(link)")
        } catch {
            log("Could not link \(link): \(error.localizedDescription)")
        }
    }

    // MARK: Uninstall

    /// Removes our hooks, the SwiftBar link, the login item and the stable asb. State and config go
    /// too when `purge` is set or `confirmPurge` says yes.
    public func uninstall(purge: Bool, confirmPurge: () -> Bool = { false }) throws {
        if let settings = try readSettings(backup: true) {
            try writeSettings(HookSettings.uninstall(settings))
            log("Removed the hooks from \(settingsFile)")
        }
        if let dir = swiftBarDir, !dir.isEmpty {
            let link = (dir as NSString).appendingPathComponent(Self.pluginName)
            // Only our link: one pointing at a plugin file of this project.
            if let target = try? fm.destinationOfSymbolicLink(atPath: link),
               target == pluginFile || target.hasSuffix("/swiftbar/\(Self.pluginName)") {
                try? fm.removeItem(atPath: link)
                log("Removed \(link)")
            }
        }
        if fm.fileExists(atPath: loginItemFile) {
            try? fm.removeItem(atPath: loginItemFile)
            log("Removed \(loginItemFile)")
        }
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
