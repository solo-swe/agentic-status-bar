import Foundation
import Testing
@testable import ASBCore

private let plugin = "/p/plugin.5s.sh"
private let now: Int64 = 1_792_891_080_000

private func render(
    _ sessions: [(String, String)], config: String = "stale_minutes=0", herdr: Bool = false, mutes: String? = nil,
    loginItem: Bool = false, target: SwiftBarRenderer.Target = .plugin(plugin), invalid: [String] = []
) -> [String] {
    var inputs = SnapshotInputs(now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!, configText: config, mutesText: mutes)
    inputs.stateFiles = sessions.map { id, fields in
        RawFile(path: "state/\(id).json", contents: Data(#"{"v":1,"sessionId":"\#(id)","updatedAt":\#(now),\#(fields)}"#.utf8))
    } + invalid.enumerated().map { RawFile(path: "state/bad\($0.offset).json", contents: Data($0.element.utf8)) }
    if herdr { inputs.herdrInstalled = true; inputs.herdrList = "{}" }
    let snapshot = Engine.snapshot(inputs).snapshot
    let text = SwiftBarRenderer.render(
        snapshot, settings: .init(config: Config.parse(config), startsAtLogin: loginItem), target: target)
    return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

@Test func noSessionsShowsThePlaceholderAndEndsWithRefresh() {
    let lines = render([])
    #expect(lines[0] == ":sparkle: | sfcolor=#C7C7CC,#48484A color=#C7C7CC,#48484A")
    #expect(lines[1] == "---")
    #expect(lines[2] == "No Claude Code sessions | color=gray")
    #expect(lines.suffix(3) == ["---", "Refresh | refresh=true", ""])
}

@Test func theMenuBarLineHasTheSymbolInlineThenTheCount() {
    #expect(render([("a", #""state":"idle""#)])[0] == ":zzz: 1 | sfcolor=#B25000,#FFD60A color=#B25000,#FFD60A")
}

@Test func invalidFilesAreReportedUnderTheHeader() {
    let lines = render([("a", #""state":"busy""#)], invalid: ["not json"])
    #expect(lines[0].hasPrefix(":exclamationmark.triangle: 1 | "))
    #expect(lines[2] == "1 state file(s) could not be read | color=gray")
}

@Test func aFocusableRowClicksToFocusAndHasEveryAction() {
    let lines = render([("s1", #""state":"idle","cwd":"/x/p","herdrPane":"w2:p1","transcriptPath":"/t.jsonl","stateSince":\#(now - 60_000)"#)], herdr: true)
    #expect(lines[2] == ":zzz: p                                                 idle · 1m | font=Menlo size=12 sfcolor=#B25000,#FFD60A bash=\"\(plugin)\" param1=focus param2=s1 terminal=false")
    #expect(Array(lines[3...8]) == [
        "--Mute project for 1 hour | bash=\"\(plugin)\" param1=mute-hour param2=s1 terminal=false refresh=true",
        "--Mute project for today | bash=\"\(plugin)\" param1=mute-today param2=s1 terminal=false refresh=true",
        "--Copy session ID | bash=\"\(plugin)\" param1=copy-id param2=s1 terminal=false",
        "--Copy working directory | bash=\"\(plugin)\" param1=copy-cwd param2=s1 terminal=false",
        "--Open folder in Finder | bash=\"\(plugin)\" param1=open-folder param2=s1 terminal=false",
        "--Reveal transcript | bash=\"\(plugin)\" param1=reveal-transcript param2=s1 terminal=false",
    ])
}

@Test func aRowOutsideHerdrSaysWhyAndHasNoClick() {
    let lines = render([("s1", #""state":"busy""#)])
    #expect(lines[2].hasSuffix("| font=Menlo size=12 sfcolor=#6E6E73,#AEAEB2"))
    #expect(lines[3] == "--Not in herdr: click to focus is unavailable | color=gray")
    // Without a cwd: no mute, no folder; without a transcript: no reveal.
    #expect(lines[4].hasPrefix("--Copy session ID"))
    #expect(lines[5].hasPrefix("--Copy working directory"))
    #expect(lines[6] == "---")
}

@Test func aMutedRowOffersUnmuteAndTheFooterUnmuteAll() {
    let mutes = #"{"/x/p":{"until":\#(now + 3_600_000),"at":\#(now - 1000),"today":false}}"#
    let lines = render([("s1", #""state":"idle","cwd":"/x/p""#)], mutes: mutes)
    #expect(lines[0] == ":bell.slash: | sfcolor=#8E8E93,#98989D color=#8E8E93,#98989D")
    #expect(lines[2].contains("idle · muted until 19:18 | "))
    #expect(lines[4] == "--Unmute project | bash=\"\(plugin)\" param1=unmute param2=s1 terminal=false refresh=true")
    #expect(lines.contains("Unmute all projects | bash=\"\(plugin)\" param1=unmute-all terminal=false refresh=true"))
}

@Test func subagentRowsAreIndentedAndGray() {
    let lines = render([("s1", #""state":"busy","subagents":{"a1":{"type":"Explore","since":\#(now - 12_000)}}"#)])
    let label = "↳ subagent: Explore" + String(repeating: " ", count: 48 - 19)
    #expect(lines.contains("  \(label)  working · 12s | font=Menlo size=12 color=gray"))
}

@Test func theFooterShowsCurrentSettings() {
    let lines = render([], config: "show_headless=0\nstale_minutes=10\ntheme=monochrome\ninstant_refresh=0", loginItem: true)
    let run = { (args: String) in " | bash=\"\(plugin)\" \(args) terminal=false refresh=true" }
    #expect(lines.contains("Interactive" + run("param1=toggle param2=show_interactive") + " checked=true"))
    #expect(lines.contains("Headless (claude -p)" + run("param1=toggle param2=show_headless")))
    #expect(lines.contains("--Start SwiftBar at login" + run("param1=login") + " checked=true"))
    #expect(lines.contains("----Monochrome" + run("param1=set param2=theme param3=monochrome") + " checked=true"))
    #expect(lines.contains("----Default" + run("param1=set param2=theme param3=default")))
    #expect(lines.contains("----10 minutes" + run("param1=set param2=stale_minutes param3=10") + " checked=true"))
    #expect(lines.contains("--Refresh instantly on changes" + run("param1=toggle param2=instant_refresh")))
    #expect(lines.contains("--Use Claude Code session registry" + run("param1=toggle param2=use_registry") + " checked=true"))
    #expect(lines.contains("-------"))
    #expect(!lines.contains { $0.hasPrefix("Unmute all") })
}

@Test func theAsbTargetCallsAsbAction() {
    let lines = render([("s1", #""state":"busy""#)], target: .asb("/bin/asb"))
    #expect(lines.contains("--Copy session ID | bash=\"/bin/asb\" param1=action param2=copy-id param3=s1 terminal=false"))
    #expect(lines.contains("Interactive | bash=\"/bin/asb\" param1=action param2=toggle param3=show_interactive terminal=false refresh=true checked=true"))
}
