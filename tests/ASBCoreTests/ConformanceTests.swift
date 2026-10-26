import Foundation
import Testing
@testable import ASBCore

// Runs every case in tests/conformance/ (see its README) through the engine.

private let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let casesDir = testsDir.appendingPathComponent("conformance")
private let transcriptFixtures = testsDir.appendingPathComponent("fixtures/transcripts")

/// Case names: directories, and single-file cases without their `.case.json` suffix.
private func caseNames() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: casesDir.path)) ?? []
    return names.compactMap { name in
        if name.hasSuffix(".case.json") { return name }
        var isDir: ObjCBool = false
        let isCaseDir = FileManager.default.fileExists(atPath: casesDir.appendingPathComponent(name).path, isDirectory: &isDir)
            && isDir.boolValue
        return isCaseDir ? name : nil
    }.sorted()
}

@Test func conformanceCasesExist() {
    #expect(!caseNames().isEmpty, "no cases found in \(casesDir.path)")
}

@Test(arguments: caseNames())
func conformance(_ name: String) throws {
    let loaded = try loadCase(casesDir.appendingPathComponent(name))
    if let why = loaded.pending {
        withKnownIssue("pending: \(why)") {
            try check(loaded)
        }
    } else {
        try check(loaded)
    }
}

private func check(_ loaded: LoadedCase) throws {
    for mismatch in try mismatches(loaded) {
        Issue.record(Comment(rawValue: mismatch))
    }
}

/// A case, from either format.
private struct LoadedCase {
    var inputs: SnapshotInputs
    var expected: Data
    var expectedDead: [String]
    var pending: String?
}

private func loadCase(_ url: URL) throws -> LoadedCase {
    url.lastPathComponent.hasSuffix(".case.json") ? try loadFileCase(url) : try loadDirectoryCase(url)
}

/// Runs one case and describes every way the engine's result differs from it; empty when it matches.
private func mismatches(_ loaded: LoadedCase) throws -> [String] {
    let result = Engine.snapshot(loaded.inputs)
    var out: [String] = []
    let expected = try canonical(loaded.expected)
    let actual = try canonical(result.snapshot.encodedJSON())
    if actual != expected {
        out.append("snapshot differs:\n\(lineDiff(expected: expected, actual: actual))")
    }
    if result.deadFiles.sorted() != loaded.expectedDead.sorted() {
        out.append("dead files differ: expected \(loaded.expectedDead.sorted()), got \(result.deadFiles.sorted())")
    }
    return out
}

// MARK: Directory cases

private struct Clock: Decodable {
    var now_ms: Int64
    var tz: String
}

private func loadDirectoryCase(_ dir: URL) throws -> LoadedCase {
    let fm = FileManager.default
    let input = dir.appendingPathComponent("input")
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
    let mtimes = read("transcripts.json").flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]
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

    let deadURL = dir.appendingPathComponent("expected-dead.json")
    let dead = fm.fileExists(atPath: deadURL.path) ? try JSONDecoder().decode([String].self, from: Data(contentsOf: deadURL)) : []
    let pendingURL = dir.appendingPathComponent("pending")
    let pending = fm.fileExists(atPath: pendingURL.path)
        ? (try? String(contentsOf: pendingURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : nil
    return LoadedCase(
        inputs: inputs, expected: try Data(contentsOf: dir.appendingPathComponent("expected.json")),
        expectedDead: dead, pending: pending)
}

// MARK: Single-file cases

private func loadFileCase(_ url: URL) throws -> LoadedCase {
    guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
          let input = root["input"] as? [String: Any], let expected = root["expected"],
          let clock = input["clock"] as? [String: Any], let now = (clock["now_ms"] as? NSNumber)?.int64Value
    else { throw CaseError.malformed(url.lastPathComponent) }

    var inputs = SnapshotInputs(now: now, timeZone: TimeZone(identifier: clock["tz"] as? String ?? "UTC") ?? .gmt)
    inputs.stateFiles = try rawFiles(input["state"], prefix: "state")
    inputs.registryFiles = try rawFiles(input["registry"], prefix: "registry")
    for (name, spec) in (input["transcripts"] as? [String: Any] ?? [:]) {
        inputs.transcripts["transcripts/\(name)"] = try transcript(spec as? [String: Any] ?? [:])
    }
    if let processes = input["processes"] {
        inputs.processes = try JSONDecoder().decode(
            [ProcessRecord].self, from: JSONSerialization.data(withJSONObject: processes))
    }
    if let herdr = input["herdr"] {
        inputs.herdrList = try text(herdr)
        inputs.herdrInstalled = true
    }
    inputs.configText = try input["config"].map(text)
    inputs.mutesText = try input["mutes"].map(text)
    return LoadedCase(
        inputs: inputs,
        expected: try JSONSerialization.data(withJSONObject: expected),
        expectedDead: root["expectedDead"] as? [String] ?? [],
        pending: root["pending"] as? String)
}

private enum CaseError: Error {
    case malformed(String)
}

/// A string is used as is (to give corrupt contents); anything else is encoded as JSON.
private func text(_ value: Any) throws -> String {
    if let string = value as? String { return string }
    return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self)
}

private func rawFiles(_ value: Any?, prefix: String) throws -> [RawFile] {
    try (value as? [String: Any] ?? [:]).sorted { $0.key < $1.key }.map { name, contents in
        RawFile(path: "\(prefix)/\(name)", contents: Data(try text(contents).utf8))
    }
}

/// A transcript: a fixture from tests/fixtures/transcripts, then `lines`, then `repeat.times` copies of `repeat.line`.
private func transcript(_ spec: [String: Any]) throws -> TranscriptInput {
    var data = Data()
    if let fixture = spec["fixture"] as? String {
        data.append(try Data(contentsOf: transcriptFixtures.appendingPathComponent("\(fixture).jsonl")))
    }
    for line in spec["lines"] as? [Any] ?? [] {
        data.append(Data((try text(line) + "\n").utf8))
    }
    if let rep = spec["repeat"] as? [String: Any], let line = rep["line"], let times = rep["times"] as? Int {
        let one = Data((try text(line) + "\n").utf8)
        for _ in 0..<times { data.append(one) }
    }
    return TranscriptInput(mtime: (spec["mtime"] as? NSNumber)?.int64Value ?? 0, contents: data)
}

// MARK: The runner itself: a wrong expectation must be reported, a right one must not.

private func makeCase(expected: String, dead: [String] = []) throws -> LoadedCase {
    LoadedCase(
        inputs: SnapshotInputs(now: 1_792_891_080_000, timeZone: .gmt),
        expected: Data(expected.utf8), expectedDead: dead, pending: nil)
}

private let emptySnapshot = """
    {"activeMutes":0,"generatedAt":1792891080000,"header":{"color":"#C7C7CC,#48484A","state":"none","symbol":"sparkle"},
     "invalidFiles":0,"sessions":[],"version":1}
    """

@Test func runnerAcceptsAMatchingCase() throws {
    #expect(try mismatches(makeCase(expected: emptySnapshot)).isEmpty)
}

@Test func runnerReportsADifferentSnapshotWithTheDifferingLine() throws {
    let found = try mismatches(makeCase(expected: emptySnapshot.replacingOccurrences(of: #""version":1"#, with: #""version":2"#)))
    #expect(found.count == 1)
    #expect(found.first?.contains(#"expected:   "version" : 2"#) == true)
}

@Test func runnerReportsMissingDeadFiles() throws {
    #expect(try mismatches(makeCase(expected: emptySnapshot, dead: ["state/s1.json"])).first?.hasPrefix("dead files differ") == true)
}

@Test func singleFileCasesLoadEveryInput() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("asb-\(UUID().uuidString).case.json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("""
        {"pending": "why", "expectedDead": ["state/a.json"],
         "input": {"clock": {"now_ms": 5, "tz": "UTC"},
                   "state": {"a.json": {"v": 1, "sessionId": "a"}, "b.json": "not json"},
                   "registry": {"1.json": {"pid": 1}},
                   "transcripts": {"t.jsonl": {"fixture": "completed-turn", "lines": [{"type": "x"}], "repeat": {"line": "y", "times": 2}, "mtime": 9}},
                   "processes": [{"pid": 1, "ppid": 0, "start": 2, "comm": "c"}],
                   "herdr": {"result": {"agents": []}}, "config": "icon=bolt\\n", "mutes": {}},
         "expected": {"version": 1}}
        """.utf8).write(to: url)
    let loaded = try loadCase(url)
    #expect(loaded.pending == "why" && loaded.expectedDead == ["state/a.json"])
    #expect(loaded.inputs.now == 5 && loaded.inputs.stateFiles.map(\.path) == ["state/a.json", "state/b.json"])
    #expect(String(decoding: loaded.inputs.stateFiles[1].contents, as: UTF8.self) == "not json")
    #expect(loaded.inputs.registryFiles.count == 1 && loaded.inputs.processes.count == 1)
    let t = try #require(loaded.inputs.transcripts["transcripts/t.jsonl"])
    #expect(t.mtime == 9 && String(decoding: t.contents, as: UTF8.self).hasSuffix("{\"type\":\"x\"}\ny\ny\n"))
    #expect(loaded.inputs.herdrInstalled && loaded.inputs.configText == "icon=bolt\n" && loaded.inputs.mutesText == "{}")
}

// MARK: Comparing

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
