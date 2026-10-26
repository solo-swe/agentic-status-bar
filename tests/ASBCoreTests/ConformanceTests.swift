import Foundation
import Testing
@testable import ASBCore

// Runs every case in tests/conformance/ (see its README) through the engine.

private let casesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("conformance")

private func caseNames() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: casesDir.path)) ?? []
    return names.filter { name in
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: casesDir.appendingPathComponent(name).path, isDirectory: &isDir)
            && isDir.boolValue
    }.sorted()
}

@Test func conformanceCasesExist() {
    #expect(!caseNames().isEmpty, "no cases found in \(casesDir.path)")
}

@Test(arguments: caseNames())
func conformance(_ name: String) throws {
    let dir = casesDir.appendingPathComponent(name)
    let pending = dir.appendingPathComponent("pending")
    if FileManager.default.fileExists(atPath: pending.path) {
        let why = (try? String(contentsOf: pending, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        withKnownIssue("pending: \(why)") {
            try check(dir)
        }
    } else {
        try check(dir)
    }
}

private func check(_ dir: URL) throws {
    for mismatch in try mismatches(dir) {
        Issue.record(Comment(rawValue: mismatch))
    }
}

/// Runs one case and describes every way the engine's result differs from it; empty when it matches.
private func mismatches(_ dir: URL) throws -> [String] {
    let inputs = try loadInputs(dir.appendingPathComponent("input"))
    let result = Engine.snapshot(inputs)
    var out: [String] = []

    let expected = try canonical(Data(contentsOf: dir.appendingPathComponent("expected.json")))
    let actual = try canonical(result.snapshot.encodedJSON())
    if actual != expected {
        out.append("snapshot differs:\n\(lineDiff(expected: expected, actual: actual))")
    }

    let deadURL = dir.appendingPathComponent("expected-dead.json")
    let expectedDead = FileManager.default.fileExists(atPath: deadURL.path)
        ? try JSONDecoder().decode([String].self, from: Data(contentsOf: deadURL)) : []
    if result.deadFiles.sorted() != expectedDead.sorted() {
        out.append("dead files differ: expected \(expectedDead.sorted()), got \(result.deadFiles.sorted())")
    }
    return out
}

// The runner itself: a wrong expectation must be reported, a right one must not.

private func makeCase(expected: String, dead: String? = nil) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("asb-conformance-\(UUID().uuidString)")
    let input = dir.appendingPathComponent("input")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    try Data(#"{"now_ms": 1792891080000, "tz": "UTC"}"#.utf8).write(to: input.appendingPathComponent("clock.json"))
    try Data(expected.utf8).write(to: dir.appendingPathComponent("expected.json"))
    if let dead {
        try Data(dead.utf8).write(to: dir.appendingPathComponent("expected-dead.json"))
    }
    return dir
}

private let emptySnapshot = """
    {"activeMutes":0,"generatedAt":1792891080000,"header":{"color":"#C7C7CC,#48484A","state":"none","symbol":"sparkle"},
     "invalidFiles":0,"sessions":[],"version":1}
    """

@Test func runnerAcceptsAMatchingCase() throws {
    let dir = try makeCase(expected: emptySnapshot)
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(try mismatches(dir).isEmpty)
}

@Test func runnerReportsADifferentSnapshotWithTheDifferingLine() throws {
    let dir = try makeCase(expected: emptySnapshot.replacingOccurrences(of: #""version":1"#, with: #""version":2"#))
    defer { try? FileManager.default.removeItem(at: dir) }
    let found = try mismatches(dir)
    #expect(found.count == 1)
    #expect(found.first?.contains(#"expected:   "version" : 2"#) == true)
}

@Test func runnerReportsMissingDeadFiles() throws {
    let dir = try makeCase(expected: emptySnapshot, dead: #"["state/s1.json"]"#)
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(try mismatches(dir).first?.hasPrefix("dead files differ") == true)
}

private struct Clock: Decodable {
    var now_ms: Int64
    var tz: String
}

private func loadInputs(_ input: URL) throws -> SnapshotInputs {
    let fm = FileManager.default
    func read(_ name: String) -> Data? { try? Data(contentsOf: input.appendingPathComponent(name)) }
    func files(_ sub: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: input.appendingPathComponent(sub).path)) ?? []).sorted()
    }

    let clock = try JSONDecoder().decode(Clock.self, from: read("clock.json") ?? Data())
    var inputs = SnapshotInputs(now: clock.now_ms, timeZone: TimeZone(identifier: clock.tz) ?? .gmt)

    inputs.stateFiles = files("state").compactMap { name in
        read("state/\(name)").map { RawFile(path: "state/\(name)", contents: $0) }
    }
    inputs.registryFiles = files("registry").compactMap { name in
        read("registry/\(name)").map { RawFile(path: "registry/\(name)", contents: $0) }
    }
    let mtimes = (read("transcripts.json")).flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]
    for name in files("transcripts") {
        if let data = read("transcripts/\(name)") {
            inputs.transcripts["transcripts/\(name)"] = TranscriptInput(mtime: mtimes[name] ?? 0, contents: data)
        }
    }
    if let data = read("processes.json") {
        inputs.processes = try JSONDecoder().decode([ProcessRecord].self, from: data)
    }
    if let data = read("herdr.json") {
        inputs.herdrList = String(decoding: data, as: UTF8.self)
        inputs.herdrInstalled = true
    }
    inputs.configText = read("config").map { String(decoding: $0, as: UTF8.self) }
    inputs.mutesText = read("mutes").map { String(decoding: $0, as: UTF8.self) }
    return inputs
}

/// JSON re-encoded with sorted keys and indentation, so equal values give equal text.
private func canonical(_ data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    let out = try JSONSerialization.data(
        withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed])
    return String(decoding: out, as: UTF8.self)
}

private func lineDiff(expected: String, actual: String) -> String {
    let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
    let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
    var out: [String] = []
    for i in 0..<max(e.count, a.count) {
        let el = i < e.count ? String(e[i]) : "<none>"
        let al = i < a.count ? String(a[i]) : "<none>"
        if el != al {
            out.append("line \(i + 1):\n  expected: \(el)\n  actual:   \(al)")
        }
    }
    return out.joined(separator: "\n") + "\n--- expected ---\n\(expected)\n--- actual ---\n\(actual)"
}
