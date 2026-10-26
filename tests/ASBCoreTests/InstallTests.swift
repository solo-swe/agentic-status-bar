import Foundation
import Testing
@testable import ASBCore

private let fixtureSettings = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/settings.json")

// MARK: OrderedJSON

@Test func orderedJSONKeepsKeyOrderAndNumberSpelling() throws {
    let text = #"{"z": 1, "a": {"y": 2.50, "b": [true, null, "x\"\né"]}, "m": -3e2}"#
    let json = try OrderedJSON.parse(Data(text.utf8))
    guard case .object(let pairs) = json else { Issue.record("not an object"); return }
    #expect(pairs.map(\.0) == ["z", "a", "m"])
    #expect(json["a"]?["y"] == .number("2.50") && json["m"] == .number("-3e2"))
    #expect(json["a"]?["b"]?.arrayValue?[2] == .string("x\"\né"))
    #expect(try OrderedJSON.parse(Data(json.serialized().utf8)) == json)
}

@Test func orderedJSONWritesLikeJq() throws {
    let json = try OrderedJSON.parse(Data(#"{"a":[],"b":{},"c":[1,{"d":"/x"}]}"#.utf8))
    #expect(json.serialized() == """
        {
          "a": [],
          "b": {},
          "c": [
            1,
            {
              "d": "/x"
            }
          ]
        }

        """)
}

@Test(arguments: ["", "not json", "{", #"{"a" 1}"#, "[1,]", "{} x", "01x", #""unterminated"#])
func orderedJSONRejectsInvalidInput(_ text: String) {
    #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse(Data(text.utf8)) }
}

@Test func subscriptSetsReplacesAndRemovesInPlace() {
    var json = OrderedJSON.object([("a", .number("1")), ("b", .number("2"))])
    json["a"] = .number("9")
    json["c"] = .null
    json["b"] = nil
    guard case .object(let pairs) = json else { return }
    #expect(pairs.map(\.0) == ["a", "c"] && json["a"] == .number("9"))
}

// MARK: Hook settings

@Test func installAddsOneAsyncHookPerEvent() throws {
    let settings = HookSettings.install(.object([]), command: HookSettings.command(asb: "/a b/asb"))
    #expect(HookSettings.count(settings) == 9)
    let hook = settings["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first
    #expect(hook?["command"] == .string("'/a b/asb' hook # agentic-status-bar"))
    #expect(hook?["async"] == .bool(true) && hook?["timeout"] == .number("10") && hook?["type"] == .string("command"))
}

@Test func installKeepsOtherSettingsAndHooksInOrder() throws {
    let original = try OrderedJSON.parse(Data(contentsOf: fixtureSettings))
    let installed = HookSettings.install(original, command: "x # agentic-status-bar")
    guard case .object(let pairs) = installed else { return }
    #expect(pairs.map(\.0) == ["permissions", "hooks"])
    #expect(installed["permissions"] == original["permissions"])
    #expect(installed["hooks"]?["SessionStart"]?.arrayValue?.first == original["hooks"]?["SessionStart"]?.arrayValue?.first)
    #expect(installed["hooks"]?["PostToolUse"]?.arrayValue?.first == original["hooks"]?["PostToolUse"]?.arrayValue?.first)
    guard case .object(let events)? = installed["hooks"] else { return }
    #expect(Array(events.map(\.0).prefix(2)) == ["SessionStart", "PostToolUse"])
}

@Test func installTwiceAddsNothingTheSecondTime() {
    let once = HookSettings.install(.object([]), command: "x # agentic-status-bar")
    #expect(HookSettings.install(once, command: "x # agentic-status-bar") == once)
}

@Test func installReplacesTheShellHooks() {
    let shell = HookSettings.install(.object([]), command: "'/repo/hooks/state-hook.sh' # swiftbar-claudecode-minimal")
    #expect(HookSettings.count(shell, markers: [HookSettings.oldMarker]) == 9)
    let swift = HookSettings.install(shell, command: "x # agentic-status-bar")
    #expect(HookSettings.count(swift, markers: [HookSettings.oldMarker]) == 0)
    #expect(HookSettings.count(swift) == 9)
}

@Test func uninstallRestoresTheSettingsExactly() throws {
    let original = try OrderedJSON.parse(Data(contentsOf: fixtureSettings))
    #expect(HookSettings.uninstall(HookSettings.install(original, command: "x # agentic-status-bar")) == original)
}

@Test func uninstallKeepsAGroupThatMixesOurHookWithOthers() throws {
    var s = HookSettings.install(.object([]), command: "x # agentic-status-bar")
    var stop = s["hooks"]!["Stop"]!.arrayValue!
    var group = stop[0]
    group["hooks"] = .array(group["hooks"]!.arrayValue! + [.object([("type", .string("command")), ("command", .string("say done"))])])
    stop[0] = group
    var hooks = s["hooks"]!
    hooks["Stop"] = .array(stop)
    s["hooks"] = hooks
    let removed = HookSettings.uninstall(s)
    #expect(removed["hooks"]?["Stop"] == .array([.object([("hooks", .array([.object([("type", .string("command")), ("command", .string("say done"))])]))])]))
    #expect(HookSettings.count(removed) == 0)
}

@Test func uninstallRemovesTheHooksKeyWhenOnlyOursWereThere() throws {
    let model = try OrderedJSON.parse(Data(#"{"model":"opus"}"#.utf8))
    #expect(HookSettings.uninstall(HookSettings.install(model, command: "x # agentic-status-bar")) == model)
}

// MARK: Installer

private struct Home {
    let root: URL
    var settings: String { root.appendingPathComponent(".claude/settings.json").path }
    var stable: String { root.appendingPathComponent("Library/Application Support/agentic-status-bar/bin/asb").path }
    var source: String { root.appendingPathComponent("build/asb").path }
    var plugin: String { root.appendingPathComponent("repo/swiftbar/agentic-status-bar.5s.sh").path }
    var swiftBar: String { root.appendingPathComponent("swiftbar-plugins").path }
    var link: String { swiftBar + "/agentic-status-bar.5s.sh" }
    var oldLink: String { swiftBar + "/swiftbar-claudecode-minimal.5s.sh" }
    var login: String { root.appendingPathComponent("Library/LaunchAgents/agentic-status-bar.start-swiftbar.plist").path }
    var oldLogin: String { root.appendingPathComponent("Library/LaunchAgents/swiftbar-claudecode-minimal.start-swiftbar.plist").path }
    var oldState: String { root.appendingPathComponent(".claude/swiftbar-claudecode-minimal").path }
    var oldConfig: String { root.appendingPathComponent(".config/swiftbar-claudecode-minimal/config").path }
    var state: String { root.appendingPathComponent(".claude/agentic-status-bar").path }
    var config: String { root.appendingPathComponent(".config/agentic-status-bar/config").path }

    init(settings: Data? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("asb-install-\(UUID().uuidString)")
        let fm = FileManager.default
        for dir in [".claude", "build", "repo/swiftbar"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: source))
        try Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: plugin))
        if let settings { try settings.write(to: URL(fileURLWithPath: self.settings)) }
    }

    func installer(swiftBarDir: String? = "default", now: Date = Date()) -> Installer {
        var i = Installer(settingsFile: settings, stableBinary: stable, sourceBinary: source, swiftBarDir: swiftBarDir == "default" ? swiftBar : swiftBarDir, loginItemFile: login,
                          stateDir: state, configFile: config)
        i.now = now
        i.log = { _ in }
        i.old = .init(stateDir: oldState, configFile: oldConfig, loginItemFile: oldLogin)
        return i
    }

    func readSettings() throws -> OrderedJSON { try OrderedJSON.parse(Data(contentsOf: URL(fileURLWithPath: settings))) }
}

@Test func installCopiesAsbRegistersHooksAndRemovesTheSwiftBarPlugin() throws {
    let home = try Home(settings: Data(contentsOf: fixtureSettings))
    let fm = FileManager.default
    try fm.createDirectory(atPath: home.swiftBar, withIntermediateDirectories: true)
    try fm.createSymbolicLink(atPath: home.link, withDestinationPath: home.plugin)
    try fm.createDirectory(atPath: (home.login as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: URL(fileURLWithPath: home.login))
    try home.installer().install()
    #expect(fm.isExecutableFile(atPath: home.stable))
    let settings = try home.readSettings()
    #expect(HookSettings.count(settings) == 9)
    #expect(settings["hooks"]?["Stop"]?.arrayValue?.last?["hooks"]?.arrayValue?.first?["command"]
            == .string("'\(home.stable)' hook # agentic-status-bar"))
    #expect((try? fm.destinationOfSymbolicLink(atPath: home.link)) == nil)
    #expect(!fm.fileExists(atPath: home.login))
}

@Test func hooksInstalledFollowsTheSettings() throws {
    let home = try Home(settings: Data(contentsOf: fixtureSettings))
    #expect(!home.installer().hooksInstalled)
    try home.installer().install()
    #expect(home.installer().hooksInstalled)
    try home.installer().uninstall(purge: false)
    #expect(!home.installer().hooksInstalled)
    #expect(!(try Home(settings: Data("not json".utf8))).installer().hooksInstalled)
    #expect(!(try Home()).installer().hooksInstalled)
}

@Test func theStableCopyIsUpdatedWhenItDiffers() throws {
    let home = try Home()
    #expect(!home.installer().binaryIsCurrent)
    try home.installer().updateBinary()
    #expect(home.installer().binaryIsCurrent)
    try Data("#!/bin/sh\n# newer\n".utf8).write(to: URL(fileURLWithPath: home.source))
    #expect(!home.installer().binaryIsCurrent)
    try home.installer().updateBinary()
    #expect(home.installer().binaryIsCurrent)
    // Updating the copy never touches the settings.
    #expect(!FileManager.default.fileExists(atPath: home.settings))
}

@Test func installBacksUpTheSettingsFile() throws {
    let home = try Home(settings: Data(contentsOf: fixtureSettings))
    try home.installer(now: Date(timeIntervalSince1970: 0)).install()
    let backups = try FileManager.default.contentsOfDirectory(atPath: home.root.appendingPathComponent(".claude").path)
        .filter { $0.hasPrefix("settings.json.bak-agentic-status-bar-") }
    #expect(backups.count == 1)
    #expect(FileManager.default.contents(atPath: home.root.appendingPathComponent(".claude/\(backups[0])").path)
            == (try Data(contentsOf: fixtureSettings)))
}

@Test func installTwiceChangesNothingTheSecondTime() throws {
    let home = try Home(settings: Data(contentsOf: fixtureSettings))
    try home.installer().install()
    let first = try home.readSettings()
    try home.installer().install()
    #expect(try home.readSettings() == first)
}

@Test func installCreatesASettingsFileWhenThereIsNone() throws {
    let home = try Home()
    try home.installer().install()
    #expect(HookSettings.count(try home.readSettings()) == 9)
}

@Test func installRefusesToTouchAnInvalidSettingsFile() throws {
    let home = try Home(settings: Data("not json".utf8))
    #expect(throws: Installer.Failure.invalidSettings(home.settings)) { try home.installer().install() }
    #expect(try String(contentsOfFile: home.settings, encoding: .utf8) == "not json")
    let array = try Home(settings: Data("[1]".utf8))
    #expect(throws: Installer.Failure.self) { try array.installer().install() }
}

@Test func installWorksWithoutSwiftBar() throws {
    let home = try Home()
    try home.installer(swiftBarDir: nil).install()
    #expect(HookSettings.count(try home.readSettings()) == 9)
    #expect(!FileManager.default.fileExists(atPath: home.swiftBar))
}

@Test func uninstallUndoesInstall() throws {
    let home = try Home(settings: Data(contentsOf: fixtureSettings))
    try home.installer().install()
    try FileManager.default.createDirectory(atPath: (home.login as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: URL(fileURLWithPath: home.login))
    try home.installer().uninstall(purge: false)
    #expect(try home.readSettings() == (try OrderedJSON.parse(Data(contentsOf: fixtureSettings))))
    #expect(!FileManager.default.fileExists(atPath: home.link))
    #expect(!FileManager.default.fileExists(atPath: home.login))
    #expect(!FileManager.default.fileExists(atPath: home.stable))
    #expect(!FileManager.default.fileExists(atPath: home.root.appendingPathComponent("Library/Application Support/agentic-status-bar").path))
}

@Test func uninstallLeavesSomeoneElsesLinkAlone() throws {
    let home = try Home()
    try FileManager.default.createDirectory(atPath: home.swiftBar, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: home.link, withDestinationPath: "/somewhere/else.sh")
    try home.installer().uninstall(purge: false)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: home.link) == "/somewhere/else.sh")
}

@Test func uninstallKeepsStateAndConfigUnlessPurged() throws {
    let home = try Home()
    try FileManager.default.createDirectory(atPath: home.state, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: (home.config as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: URL(fileURLWithPath: home.state + "/s1.json"))
    try Data("icon=bolt\n".utf8).write(to: URL(fileURLWithPath: home.config))
    try home.installer().uninstall(purge: false)
    #expect(FileManager.default.fileExists(atPath: home.config) && FileManager.default.fileExists(atPath: home.state + "/s1.json"))
    try home.installer().uninstall(purge: false, confirmPurge: { true })
    #expect(!FileManager.default.fileExists(atPath: home.config) && !FileManager.default.fileExists(atPath: home.state))
}

@Test func installMovesTheOldStateConfigLoginItemAndLink() throws {
    let home = try Home()
    let fm = FileManager.default
    try fm.createDirectory(atPath: home.oldState, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: (home.oldConfig as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: (home.oldLogin as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: home.swiftBar, withIntermediateDirectories: true)
    try Data(#"{"v":1,"sessionId":"s1"}"#.utf8).write(to: URL(fileURLWithPath: home.oldState + "/s1.json"))
    try Data("{}".utf8).write(to: URL(fileURLWithPath: home.oldState + "/mutes"))
    try Data("x".utf8).write(to: URL(fileURLWithPath: home.oldState + "/s1.json.tmp.1"))
    try Data("theme=monochrome\n".utf8).write(to: URL(fileURLWithPath: home.oldConfig))
    try Data("x".utf8).write(to: URL(fileURLWithPath: home.oldLogin))
    try fm.createSymbolicLink(atPath: home.oldLink, withDestinationPath: "/old/repo/swiftbar/swiftbar-claudecode-minimal.5s.sh")

    try home.installer().install()
    #expect(fm.fileExists(atPath: home.state + "/s1.json") && fm.fileExists(atPath: home.state + "/mutes"))
    #expect(!fm.fileExists(atPath: home.state + "/s1.json.tmp.1"))
    #expect(try String(contentsOfFile: home.config, encoding: .utf8) == "theme=monochrome\n")
    #expect(!fm.fileExists(atPath: home.oldConfig))
    // The SwiftBar login item and link are removed, not replaced.
    #expect(!fm.fileExists(atPath: home.oldLogin) && !fm.fileExists(atPath: home.login))
    #expect((try? fm.destinationOfSymbolicLink(atPath: home.oldLink)) == nil)
    #expect((try? fm.destinationOfSymbolicLink(atPath: home.link)) == nil)
}

@Test func migrationNeverOverwritesNewFiles() throws {
    let home = try Home()
    let fm = FileManager.default
    try fm.createDirectory(atPath: home.oldState, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: home.state, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: (home.oldConfig as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try fm.createDirectory(atPath: (home.config as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: URL(fileURLWithPath: home.oldState + "/s1.json"))
    try Data("new".utf8).write(to: URL(fileURLWithPath: home.state + "/s1.json"))
    try Data("theme=monochrome\n".utf8).write(to: URL(fileURLWithPath: home.oldConfig))
    try Data("theme=default\n".utf8).write(to: URL(fileURLWithPath: home.config))
    try home.installer().install()
    #expect(try String(contentsOfFile: home.state + "/s1.json", encoding: .utf8) == "new")
    #expect(try String(contentsOfFile: home.config, encoding: .utf8) == "theme=default\n")
}

@Test func uninstallAlsoRemovesTheOldLink() throws {
    let home = try Home()
    try FileManager.default.createDirectory(atPath: home.swiftBar, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: home.oldLink, withDestinationPath: "/old/repo/swiftbar/swiftbar-claudecode-minimal.5s.sh")
    try home.installer().uninstall(purge: false)
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: home.oldLink)) == nil)
}

@Test func uninstallTwiceIsHarmless() throws {
    let home = try Home(settings: Data(contentsOf: fixtureSettings))
    try home.installer().install()
    try home.installer().uninstall(purge: false)
    let first = try home.readSettings()
    try home.installer().uninstall(purge: false)
    #expect(try home.readSettings() == first)
}
