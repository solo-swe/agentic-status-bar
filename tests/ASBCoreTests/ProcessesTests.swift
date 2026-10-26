import Foundation
import Testing
@testable import ASBCore

@Test func fakeInspectorAnswersFromItsRecords() {
    let fake = FakeProcessInspector([
        ProcessRecord(pid: 4242, ppid: 1, start: 1_792_890_000, comm: "claude", args: "claude -p hi"),
    ])
    #expect(fake.process(4242)?.comm == "claude")
    #expect(fake.process(4242)?.args == nil)
    #expect(fake.process(1) == nil)
    #expect(fake.arguments(4242) == "claude -p hi")
    #expect(fake.processes().count == 1)
}

@Test func tableInspectorReadsTheBatsFakeProcessTable() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("asb-ps-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    try "4242|1|claude|claude --resume|Mon Oct 19 09:12:03 2026\nbad line\n7001|4242|/bin/zsh|zsh -c npm test|Mon Oct 19 09:13:00 2026\n"
        .write(to: file, atomically: true, encoding: .utf8)
    let la = TimeZone(identifier: "America/Los_Angeles")!
    let inspector = TableProcessInspector(path: file.path, timeZone: la)
    #expect(inspector.processes().map(\.pid) == [4242, 7001])
    #expect(inspector.process(4242)?.start == 1_792_426_323)
    #expect(inspector.arguments(4242) == "claude --resume")
    #expect(inspector.process(7001)?.ppid == 4242)
    #expect(ProcessInspectors.fromEnvironment(["CLAUDE_STATUSBAR_PS_TABLE": file.path]) is TableProcessInspector)
}

@Test func procStartParsesWithExtraSpaces() {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    let seconds = ProcStart.parse("Mon Oct 19 09:12:03 2026", timeZone: la)
    #expect(seconds != nil)
    #expect(ProcStart.parse("  Mon  Oct 19   09:12:03 2026 ", timeZone: la) == seconds)
    #expect(ProcStart.parse("yesterday", timeZone: la) == nil)
}

@Test func procStartFormatsLikePsAndRoundTrips() throws {
    let utc = TimeZone(identifier: "UTC")!
    let seconds = try #require(ProcStart.parse("Mon Oct  5 09:12:03 2026", timeZone: utc))
    #expect(ProcStart.format(seconds, timeZone: utc) == "Mon Oct  5 09:12:03 2026")
    let later = try #require(ProcStart.parse("Mon Oct 19 09:12:03 2026", timeZone: utc))
    #expect(ProcStart.format(later, timeZone: utc) == "Mon Oct 19 09:12:03 2026")
    #expect(ProcStart.matches("Mon Oct 19 09:12:03 2026", seconds: later, timeZone: utc))
    #expect(!ProcStart.matches("Mon Oct 19 09:12:04 2026", seconds: later, timeZone: utc))
}

#if os(macOS)
@Test func darwinInspectorFindsThisProcessAndItsParent() throws {
    let inspector = DarwinProcessInspector()
    let me = try #require(inspector.process(getpid()))
    #expect(me.ppid == getppid())
    #expect(!me.comm.isEmpty)
    let now = Int64(Date().timeIntervalSince1970)
    #expect(me.start <= now && me.start > now - 86_400)
    #expect(inspector.arguments(getpid())?.isEmpty == false)
    #expect(inspector.processes().contains { $0.pid == getpid() })
    #expect(inspector.process(-1) == nil)
}

@Test func darwinStartTimeMatchesPs() throws {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-o", "lstart=", "-p", String(getpid())]
    let pipe = Pipe()
    ps.standardOutput = pipe
    try ps.run()
    ps.waitUntilExit()
    let lstart = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let me = try #require(DarwinProcessInspector().process(getpid()))
    #expect(ProcStart.matches(lstart, seconds: me.start))
}
#endif
