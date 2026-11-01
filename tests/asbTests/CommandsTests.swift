import ArgumentParser
import ASBCore
import Foundation
import Testing
@testable import asb

private let payloads = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/payloads")
/// The session ID of the fixture payloads.
private let sessionId = "3f9c2a7e-1b4d-4c8e-9a6f-2d5e8b7c1a90"

/// A temporary home, and an environment that points every path asb uses into it.
private struct TempHome {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("asb-cli-\(UUID().uuidString)")
        .resolvingSymlinksInPath().path
    var stateDir: String { root + "/.claude/agentic-status-bar" }
    var configFile: String { root + "/.config/agentic-status-bar/config" }
    var settingsFile: String { root + "/.claude/settings.json" }
    var environment: [String: String] {
        [
            "HOME": root, "ASB_STATE_DIR": stateDir, "ASB_CONFIG": configFile,
            "ASB_REGISTRY_DIR": root + "/.claude/sessions", "ASB_SETTINGS": settingsFile,
            "ASB_HERDR": root + "/no-herdr", "ASB_SWIFTBAR_DIR": "", "ASB_PS_TABLE": root + "/ps-table",
        ]
    }

    init() throws {
        try FileManager.default.createDirectory(atPath: root + "/.claude", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root + "/ps-table", contents: Data())
    }

    /// A built asb to install: any executable file will do.
    func fakeAsb() -> String {
        let path = root + "/build/asb"
        try? FileManager.default.createDirectory(atPath: root + "/build", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return path
    }

    func installer() -> Installer {
        var installer = Setup.installer(environment: environment, argv0: fakeAsb(), currentDirectory: root)
        installer.log = { _ in }
        return installer
    }

    func state() -> [String: Any]? {
        FileManager.default.contents(atPath: "\(stateDir)/\(sessionId).json")
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

// MARK: Parsing

@Test func eachSubcommandParses() throws {
    #expect(try ASB.parseAsRoot(["hook"]) is HookCommand)
    let snapshot = try #require(try ASB.parseAsRoot(["snapshot", "--json", "--pretty"]) as? SnapshotCommand)
    #expect(snapshot.json && snapshot.pretty)
    let action = try #require(try ASB.parseAsRoot(["action", "set", "theme", "monochrome"]) as? ActionCommand)
    #expect(action.name == "set" && action.arguments == ["theme", "monochrome"])
    #expect(try ASB.parseAsRoot(["install"]) is InstallCommand)
    #expect(try #require(try ASB.parseAsRoot(["uninstall", "--purge"]) as? UninstallCommand).purge)
    #expect(try !UninstallCommand.parse([]).purge)
}

@Test func unknownSubcommandsAndArgumentsAreRejected() {
    #expect(throws: (any Error).self) { try ASB.parseAsRoot(["frobnicate"]) }
    #expect(throws: (any Error).self) { try HookCommand.parse(["extra"]) }
    #expect(throws: (any Error).self) { try ActionCommand.parse([]) }
}

@Test func theVersionIsTheCoresVersion() {
    #expect(ASB.configuration.version == ASBVersion.current)
}

// MARK: hook

@Test func theHookRecordsThePayloadOnItsInput() throws {
    let home = try TempHome()
    let input = try FileHandle(forReadingFrom: payloads.appendingPathComponent("PreToolUse.json"))
    defer { try? input.close() }
    try HookCommand.parse([]).run(input: input, environment: home.environment)
    let state = try #require(home.state())
    #expect(state["state"] as? String == "busy" && state["sessionId"] as? String == sessionId)
    #expect(state["pid"] is NSNull, "no claude in the fake process table")
}

@Test func theHookIgnoresInputThatIsntAPayload() throws {
    let home = try TempHome()
    let file = home.root + "/garbage"
    FileManager.default.createFile(atPath: file, contents: Data("not json".utf8))
    let input = try #require(FileHandle(forReadingAtPath: file))
    defer { try? input.close() }
    try HookCommand.parse([]).run(input: input, environment: home.environment)
    #expect(!FileManager.default.fileExists(atPath: home.stateDir))
}

// MARK: snapshot

@Test func theSnapshotPrintsTheSessionsAsJSON() throws {
    let home = try TempHome()
    try FileManager.default.createDirectory(atPath: home.stateDir, withIntermediateDirectories: true)
    try Data(#"{"v":1,"sessionId":"s1","state":"idle","cwd":"/Users/alex/code/app"}"#.utf8)
        .write(to: URL(fileURLWithPath: home.stateDir + "/s1.json"))

    let compact = try SnapshotCommand.parse(["--json"]).output(environment: home.environment)
    #expect(compact.last == UInt8(ascii: "\n"))
    let object = try #require(try JSONSerialization.jsonObject(with: compact) as? [String: Any])
    let sessions = try #require(object["sessions"] as? [[String: Any]])
    #expect(sessions.map { $0["sessionId"] as? String } == ["s1"])
    #expect(object["header"] != nil)

    let pretty = try SnapshotCommand.parse(["--json", "--pretty"]).output(environment: home.environment)
    #expect(String(decoding: pretty, as: UTF8.self).contains("\n  "))
}

// MARK: action

@Test func anActionChangesTheConfigInTheHome() throws {
    let home = try TempHome()
    try ActionCommand.parse(["set", "theme", "monochrome"]).run(environment: home.environment)
    #expect(Config.load(Paths.from(environment: home.environment)).theme == "monochrome")
}

// MARK: install and uninstall

@Test func theInstallerIsForTheHomeAndTheAsbBeingRun() throws {
    let home = try TempHome()
    let installer = home.installer()
    #expect(installer.settingsFile == home.settingsFile)
    #expect(installer.sourceBinary == home.root + "/build/asb")
    #expect(installer.stableBinary.hasPrefix(home.root + "/Library/"))
    #expect(installer.stateDir == home.stateDir && installer.configFile == home.configFile)
    #expect(installer.swiftBarDir == nil)
}

@Test func installAddsTheHooksAndUninstallRemovesThem() throws {
    let home = try TempHome()
    let installer = home.installer()
    try InstallCommand.parse([]).run(installer)
    #expect(installer.hooksInstalled && FileManager.default.isExecutableFile(atPath: installer.stableBinary))
    try UninstallCommand.parse([]).run(installer, confirmPurge: { false })
    #expect(!installer.hooksInstalled && !FileManager.default.fileExists(atPath: installer.stableBinary))
}

@Test func uninstallPurgesTheStateAndConfigWhenAskedTo() throws {
    let home = try TempHome()
    try FileManager.default.createDirectory(atPath: home.stateDir, withIntermediateDirectories: true)
    try UninstallCommand.parse(["--purge"]).run(home.installer(), confirmPurge: { Issue.record("asked"); return false })
    #expect(!FileManager.default.fileExists(atPath: home.stateDir))
}

@Test func installAndUninstallFailOnInvalidSettings() throws {
    let home = try TempHome()
    try Data("not json".utf8).write(to: URL(fileURLWithPath: home.settingsFile))
    #expect(throws: ExitCode.failure) { try InstallCommand.parse([]).run(home.installer()) }
    #expect(throws: ExitCode.failure) {
        try UninstallCommand.parse([]).run(home.installer(), confirmPurge: { false })
    }
    #expect(try String(contentsOfFile: home.settingsFile, encoding: .utf8) == "not json")
}
