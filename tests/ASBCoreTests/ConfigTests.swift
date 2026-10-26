import Foundation
import Testing
@testable import ASBCore

private func tempFile(_ name: String = "config") -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("asb-config-\(UUID().uuidString)").appendingPathComponent(name).path
}

@Test func defaultsWithoutAConfigFile() {
    let config = Config.parse(nil)
    #expect(config.showInteractive && config.showHeadless && config.showSubagents && config.showIDE)
    #expect(config.staleMinutes == 30)
    #expect(config.useRegistry && config.instantRefresh && config.storePromptPreview)
    #expect(config.icon == "")
    #expect(config.theme == "default")
    #expect(config.stateDir == nil)
    #expect(config.iconOverrides.isEmpty && config.colorOverrides.isEmpty)
}

@Test func readsOverridesAndSkipsComments() {
    let config = Config.parse("stale_minutes=10\n# a comment\nicon=bolt\nstate_dir=~/agents\nshow_headless=0\n")
    #expect(config.staleMinutes == 10)
    #expect(config.icon == "bolt")
    #expect(config.stateDir == "~/agents")
    #expect(!config.showHeadless)
    #expect(config.useRegistry)
}

@Test func stateDirComesFromTheEnvironmentThenTheConfigThenTheDefault() {
    let home = "/Users/alex"
    let fromConfig = Config.parse("state_dir=~/agents")
    #expect(Paths.from(environment: [:], home: home).stateDir(config: fromConfig) == "/Users/alex/agents")
    #expect(Paths.from(environment: [:], home: home).stateDir(config: Config())
        == "/Users/alex/.claude/swiftbar-claudecode-minimal")
    let overridden = Paths.from(environment: ["CLAUDE_STATUSBAR_STATE_DIR": "/elsewhere"], home: home)
    #expect(overridden.stateDir(config: fromConfig) == "/elsewhere")
}

@Test func homeComesFromTheHomeVariable() {
    let paths = Paths.from(environment: ["HOME": "/tmp/fake-home"])
    #expect(paths.home == "/tmp/fake-home")
    #expect(paths.loginItemFile.hasPrefix("/tmp/fake-home/Library/LaunchAgents/"))
    #expect(Paths.from(environment: [:]).home == NSHomeDirectory())
}

@Test func pathsDefaultsAndOverrides() {
    let paths = Paths.from(environment: [:], home: "/Users/alex")
    #expect(paths.configFile == "/Users/alex/.config/swiftbar-claudecode-minimal/config")
    #expect(paths.registryDir == "/Users/alex/.claude/sessions")
    let custom = Paths.from(
        environment: ["CLAUDE_STATUSBAR_CONFIG": "/tmp/c", "CLAUDE_STATUSBAR_REGISTRY_DIR": "/tmp/r"], home: "/h")
    #expect(custom.configFile == "/tmp/c")
    #expect(custom.registryDir == "/tmp/r")
}

@Test func ignoresUnknownKeysAndUnsafeValues() {
    let config = Config.parse("""
        evil=1
        icon=$(touch /tmp/pwned)
        stale_minutes=`touch /tmp/pwned2`
        use_registry=0;touch /tmp/pwned3
        """)
    #expect(config.icon == "")
    #expect(config.staleMinutes == 30)
    #expect(config.useRegistry)
}

@Test func colorKeysTakeHexOrALightDarkPairOnly() {
    let config = Config.parse("""
        color_idle=#123abc,#FFFFFF
        color_busy=#00FF00
        color_waiting=red
        color_muted=#12345
        color_none=#123456;touch x
        icon_idle=moon.zzz
        theme=high_contrast
        """)
    #expect(config.colorOverrides == ["idle": "#123abc,#FFFFFF", "busy": "#00FF00"])
    #expect(config.iconOverrides == ["idle": "moon.zzz"])
    #expect(config.theme == "high_contrast")
}

@Test func setChangesOneKeyAndKeepsTheOthers() throws {
    let file = tempFile()
    try Config.set("icon", "bolt", in: file)
    try Config.set("stale_minutes", "10", in: file)
    try Config.set("stale_minutes", "60", in: file)
    let text = try String(contentsOfFile: file, encoding: .utf8)
    #expect(text == "icon=bolt\nstale_minutes=60\n")
    let config = Config.parse(text)
    #expect(config.staleMinutes == 60 && config.icon == "bolt")
}

@Test func setCreatesTheFileAndRejectsUnknownKeysOrBadValues() throws {
    let file = tempFile()
    #expect(try Config.set("show_headless", "0", in: file))
    #expect(try !Config.set("evil", "1", in: file))
    #expect(try !Config.set("icon", "a;b", in: file))
    #expect(try !Config.set("color_idle", "red", in: file))
    #expect(try String(contentsOfFile: file, encoding: .utf8) == "show_headless=0\n")
    #expect(try Config.set("color_idle", "#000000,#FFFFFF", in: file))
    #expect(try String(contentsOfFile: file, encoding: .utf8) == "show_headless=0\ncolor_idle=#000000,#FFFFFF\n")
}

@Test func setKeepsCommentsAndOtherLines() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(
        atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try "# settings\ntheme=monochrome\nicon=bolt\n".write(toFile: file, atomically: true, encoding: .utf8)
    try Config.set("theme", "default", in: file)
    #expect(try String(contentsOfFile: file, encoding: .utf8) == "# settings\nicon=bolt\ntheme=default\n")
}
