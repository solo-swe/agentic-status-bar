import Foundation
import Testing
@testable import ASBCore

private let la = TimeZone(identifier: "America/Los_Angeles")!
private let claude = ProcessRecord(pid: 4242, ppid: 1, start: 1_792_426_323, comm: "claude")

/// Runs the checks on one live session (pid 4242) merged with `state`, and one registry entry.
/// The fixtures use small timestamps, so C5 is off (as in tests/checks.bats).
private func reconcile(state: String, registry: String?, config: String = "") -> Engine.Reconciled {
    let base = #""v":1,"sessionId":"s1","pid":4242,"procStart":"Mon Oct 19 09:12:03 2026","cwd":"/x/proj""#
    var inputs = SnapshotInputs(now: 1_792_891_080_000, timeZone: la, configText: config + "\nstale_minutes=0\n")
    inputs.stateFiles = [RawFile(path: "state/s1.json", contents: Data("{\(base),\(state)}".utf8))]
    inputs.processes = [claude]
    if let registry {
        inputs.registryFiles = [RawFile(path: "registry/4242.json", contents: Data(registry.utf8))]
    }
    return Engine.reconcile(inputs)
}

private func only(_ r: Engine.Reconciled) throws -> ReconciledSession {
    try #require(r.sessions.count == 1)
    return r.sessions[0]
}

@Test func c2UsesANewerRegistryStatus() throws {
    let s = try only(reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"idle","statusUpdatedAt":2000}"#))
    #expect(s.shown == "idle")
    #expect(s.shownSince == 2000)
}

@Test func c2MapsANewerWaitingStatusWithItsReason() throws {
    let permission = try only(reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"waiting","waitingFor":"permission prompt","statusUpdatedAt":2000}"#))
    #expect(permission.shown == "waiting" && permission.reason == "permission")
    let question = try only(reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"waiting","waitingFor":"user input","statusUpdatedAt":2000}"#))
    #expect(question.shown == "waiting" && question.reason == "question")
}

@Test func c2IgnoresAnOlderOrEqualRegistryStatus() throws {
    for at in [2000, 3000] {
        let s = try only(reconcile(
            state: #""state":"waiting","reason":"permission","updatedAt":3000"#,
            registry: #"{"pid":4242,"sessionId":"s1","status":"busy","statusUpdatedAt":\#(at)}"#))
        #expect(s.shown == "waiting" && s.shownSince == nil)
    }
}

@Test func c2IgnoresAnEntryForAnotherSession() throws {
    let s = try only(reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"someone-else","status":"idle","statusUpdatedAt":2000,"name":"x"}"#))
    #expect(s.shown == "busy" && s.sessionName == nil)
}

@Test func c2IgnoresAnUnknownStatus() throws {
    let r = reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"thinking-hard","statusUpdatedAt":2000}"#)
    #expect(try only(r).shown == "busy")
    #expect(!r.registrySchemaIssue)
}

@Test func c2FlagsAnEntryWithoutStatus() throws {
    let r = reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"s1","statusUpdatedAt":2000}"#)
    #expect(try only(r).shown == "busy")
    #expect(r.registrySchemaIssue)
}

@Test func c2IsOffWhenUseRegistryIs0() throws {
    let r = reconcile(
        state: #""state":"busy","updatedAt":1000"#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"idle","statusUpdatedAt":2000,"name":"n","nameSource":"user"}"#,
        config: "use_registry=0\n")
    let s = try only(r)
    #expect(s.shown == "busy" && s.sessionName == nil)
}

@Test func c2TakesAUserGivenNameButNotADerivedOne() throws {
    let user = try only(reconcile(
        state: #""state":"idle""#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"idle","name":"parser-rewrite","nameSource":"user"}"#))
    #expect(user.sessionName == "parser-rewrite")
    let derived = try only(reconcile(
        state: #""state":"idle""#,
        registry: #"{"pid":4242,"sessionId":"s1","status":"idle","name":"s1-a3","nameSource":"derived"}"#))
    #expect(derived.sessionName == nil)
}

@Test func corruptRegistryFilesAreIgnored() throws {
    let r = reconcile(state: #""state":"busy","updatedAt":1000"#, registry: "garbage")
    #expect(try only(r).shown == "busy")
    #expect(!r.registrySchemaIssue)
}

@Test func registryNeverTouchesSessionsWithoutPid() {
    let entries = RegistryEntry.parse([
        RawFile(path: "r", contents: Data(#"{"pid":4242,"sessionId":"s1","status":"idle","statusUpdatedAt":9}"#.utf8)),
    ])
    var file = StateFile(path: "state/s1.json", sessionId: "s1")
    file.state = "busy"
    let (sessions, _) = Checks.registry([ReconciledSession(file)], entries: entries)
    #expect(sessions[0].shown == "busy")
}
