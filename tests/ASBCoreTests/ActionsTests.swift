import Foundation
import Testing
@testable import ASBCore

/// Records commands instead of running them; `fail` names commands that should exit non-zero.
private final class FakeRunner: CommandRunner {
    struct Call: Equatable {
        var command: String
        var arguments: [String]
        var input: String?
    }
    var calls: [Call] = []
    var fail: Set<String> = []

    func run(_ command: String, _ arguments: [String], input: Data?, timeout: TimeInterval?) -> Bool {
        calls.append(Call(command: command, arguments: arguments, input: input.map { String(decoding: $0, as: UTF8.self) }))
        return !fail.contains(command)
    }
}

/// A temporary home with a state dir, and actions running against it.
private struct Fixture {
    let home: URL
    let runner = FakeRunner()
    var stateDir: URL { home.appendingPathComponent(".claude/swiftbar-claudecode-minimal") }
    var configFile: String { home.appendingPathComponent(".config/swiftbar-claudecode-minimal/config").path }
    let now: Int64 = 1_792_891_080_000

    init(herdr: String? = nil) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("asb-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/swiftbar-claudecode-minimal"),
                                                withIntermediateDirectories: true)
        self.herdr = herdr
    }
    let herdr: String?

    func addState(_ id: String, _ fields: String) throws {
        try Data(#"{"v":1,"sessionId":"\#(id)",\#(fields)}"#.utf8).write(to: stateDir.appendingPathComponent("\(id).json"))
    }

    func perform(_ name: String, _ args: String...) {
        let env = ["CLAUDE_STATUSBAR_HERDR": herdr ?? home.appendingPathComponent("no-herdr").path]
        Actions(paths: Paths.from(environment: env, home: home.path), environment: env, runner: runner,
                now: { now }, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
            .perform(name, args)
    }

    func config() -> String { (try? String(contentsOfFile: configFile, encoding: .utf8)) ?? "" }
    func mutes() -> [String: Mute] {
        Mutes.parse(try? String(contentsOf: stateDir.appendingPathComponent("mutes"), encoding: .utf8))
    }
}

// MARK: Copy, open, reveal

@Test func copyIdAndCopyCwdPutTheValueOnTheClipboard() throws {
    let f = try Fixture()
    try f.addState("abc123", #""state":"busy","cwd":"/x/p""#)
    f.perform("copy-id", "abc123")
    f.perform("copy-cwd", "abc123")
    #expect(f.runner.calls == [.init(command: "pbcopy", arguments: [], input: "abc123"),
                               .init(command: "pbcopy", arguments: [], input: "/x/p")])
}

@Test func openFolderAndRevealTranscriptCallOpen() throws {
    let f = try Fixture()
    let transcript = f.home.appendingPathComponent("t.jsonl")
    try Data().write(to: transcript)
    try f.addState("abc123", #""state":"busy","cwd":"\#(f.home.path)","transcriptPath":"\#(transcript.path)""#)
    f.perform("open-folder", "abc123")
    f.perform("reveal-transcript", "abc123")
    #expect(f.runner.calls == [.init(command: "open", arguments: [f.home.path]),
                               .init(command: "open", arguments: ["-R", transcript.path])])
}

@Test func missingFoldersAndTranscriptsOpenNothing() throws {
    let f = try Fixture()
    try f.addState("abc123", #""state":"busy","cwd":"/nonexistent","transcriptPath":"/nonexistent/t.jsonl""#)
    f.perform("open-folder", "abc123")
    f.perform("reveal-transcript", "abc123")
    #expect(f.runner.calls.isEmpty)
}

@Test func actionsIgnoreUnsafeOrUnknownSessionIds() throws {
    let f = try Fixture()
    try f.addState("abc123", #""state":"busy","cwd":"/x/p""#)
    for id in ["../abc123", "abc;rm", "", "nosuch"] {
        f.perform("copy-id", id)
        f.perform("open-folder", id)
        f.perform("mute-hour", id)
        f.perform("focus", id)
    }
    #expect(f.runner.calls.isEmpty)
    #expect(f.mutes().isEmpty)
}

// MARK: Focus

@Test func focusCallsHerdrThenRaisesTheTerminal() throws {
    let f = try Fixture(herdr: "/usr/bin/true")
    try f.addState("s1", #""state":"idle","herdrPane":"w2:p1","termBundleId":"com.mitchellh.ghostty""#)
    f.perform("focus", "s1")
    #expect(f.runner.calls == [.init(command: "/usr/bin/true", arguments: ["agent", "focus", "w2:p1"]),
                               .init(command: "open", arguments: ["-b", "com.mitchellh.ghostty"])])
}

@Test func focusDoesNothingElseWhenHerdrFails() throws {
    let f = try Fixture(herdr: "/usr/bin/true")
    f.runner.fail = ["/usr/bin/true"]
    try f.addState("s1", #""state":"idle","herdrPane":"w2:p1","termBundleId":"com.mitchellh.ghostty""#)
    f.perform("focus", "s1")
    #expect(f.runner.calls.map(\.command) == ["/usr/bin/true"])
}

@Test func focusSkipsRaisingTheTerminalWithoutABundleId() throws {
    let f = try Fixture(herdr: "/usr/bin/true")
    try f.addState("s1", #""state":"idle","herdrPane":"w2:p1""#)
    f.perform("focus", "s1")
    #expect(f.runner.calls.map(\.command) == ["/usr/bin/true"])
}

@Test func focusIgnoresUnsafePaneAndBundleValuesAndMissingHerdr() throws {
    let f = try Fixture(herdr: "/usr/bin/true")
    try f.addState("s1", #""state":"idle","herdrPane":"w2:p1; rm -rf /""#)
    f.perform("focus", "s1")
    #expect(f.runner.calls.isEmpty)
    try f.addState("s2", #""state":"idle","herdrPane":"w2:p1","termBundleId":"com.x; evil""#)
    f.perform("focus", "s2")
    #expect(f.runner.calls.map(\.command) == ["/usr/bin/true"])

    let noHerdr = try Fixture()
    try noHerdr.addState("s1", #""state":"idle","herdrPane":"w2:p1""#)
    noHerdr.perform("focus", "s1")
    #expect(noHerdr.runner.calls.isEmpty)
}

// MARK: Settings

@Test func toggleFlipsAKeyAndIgnoresUnknownKeys() throws {
    let f = try Fixture()
    f.perform("toggle", "show_headless")
    #expect(f.config() == "show_headless=0\n")
    f.perform("toggle", "show_headless")
    #expect(f.config() == "show_headless=1\n")
    f.perform("toggle", "instant_refresh")
    f.perform("toggle", "use_registry")
    f.perform("toggle", "store_prompt_preview")
    f.perform("toggle", "evil")
    f.perform("toggle", "state_dir")
    #expect(f.config() == "show_headless=1\ninstant_refresh=0\nuse_registry=0\nstore_prompt_preview=0\n")
}

@Test func setTakesOnlyTheMenusChoices() throws {
    let f = try Fixture()
    f.perform("set", "stale_minutes", "60")
    f.perform("set", "theme", "high_contrast")
    f.perform("set", "stale_minutes", "7")
    f.perform("set", "icon", "bolt")
    f.perform("set", "theme", "fancy")
    f.perform("set", "stale_minutes", "1;touch x")
    #expect(f.config() == "stale_minutes=60\ntheme=high_contrast\n")
}

@Test func revealConfigCreatesTheDefaultConfigThenRevealsIt() throws {
    let f = try Fixture()
    f.perform("reveal-config")
    let text = f.config()
    #expect(text.contains("\nstale_minutes=30\n") && text.contains("\ntheme=default\n"))
    #expect(text.contains("\n#   color_idle=#B25000,#FFD60A\n"))
    #expect(Config.parse(text) == Config())
    #expect(f.runner.calls == [.init(command: "open", arguments: ["-R", f.configFile])])
}

@Test func revealConfigKeepsAnExistingConfig() throws {
    let f = try Fixture()
    f.perform("set", "theme", "monochrome")
    f.perform("reveal-config")
    #expect(f.config() == "theme=monochrome\n")
}

@Test func theDefaultConfigKeepsOverrides() {
    let text = Actions.defaultConfig(Config.parse("icon=bolt\nicon_idle=moon.zzz\ncolor_busy=#000000"))
    #expect(text.hasSuffix("icon_idle=moon.zzz\ncolor_busy=#000000\nicon=bolt\n"))
}

@Test func loginAddsAndRemovesTheLoginItem() throws {
    let f = try Fixture()
    let item = f.home.appendingPathComponent("Library/LaunchAgents/swiftbar-claudecode-minimal.start-swiftbar.plist")
    f.perform("login")
    let plist = try #require(NSDictionary(contentsOf: item))
    #expect(plist["Label"] as? String == "swiftbar-claudecode-minimal.start-swiftbar")
    #expect(plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-g", "-b", "com.ameba.SwiftBar"])
    #expect(plist["RunAtLoad"] as? Bool == true)
    f.perform("login")
    #expect(!FileManager.default.fileExists(atPath: item.path))
}

// MARK: Mutes

@Test func muteActionsWriteTheMutesFile() throws {
    let f = try Fixture()
    try f.addState("a", #""state":"idle","cwd":"/x/alpha""#)
    try f.addState("b", #""state":"idle","cwd":"/x/beta""#)
    f.perform("mute-hour", "a")
    f.perform("mute-today", "b")
    #expect(f.mutes() == ["/x/alpha": Mute(until: f.now + 3_600_000, at: f.now, today: false),
                          "/x/beta": Mute(until: f.now + (5 * 60 + 42) * 60_000, at: f.now, today: true)])
    f.perform("unmute", "a")
    #expect(Array(f.mutes().keys) == ["/x/beta"])
    f.perform("unmute-all")
    #expect(f.mutes().isEmpty)
}

@Test func aSessionWithoutCwdCannotBeMuted() throws {
    let f = try Fixture()
    try f.addState("a", #""state":"idle""#)
    f.perform("mute-hour", "a")
    #expect(!FileManager.default.fileExists(atPath: f.stateDir.appendingPathComponent("mutes").path))
}

@Test func processRunnerReportsExitStatusFeedsInputAndTimesOut() {
    let runner = ProcessRunner(environment: ["PATH": "/usr/bin:/bin"])
    #expect(runner.run("cat", [], input: Data("hello".utf8), timeout: 2))
    #expect(!runner.run("false", [], input: nil, timeout: 2))
    #expect(!runner.run("no-such-command-xyz", [], input: nil, timeout: 2))
    let start = Date()
    #expect(!runner.run("/bin/sleep", ["5"], input: nil, timeout: 0.3))
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func unknownActionsDoNothing() throws {
    let f = try Fixture()
    f.perform("rm-rf", "/")
    #expect(f.runner.calls.isEmpty)
}
