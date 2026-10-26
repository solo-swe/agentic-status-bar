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
