import ASBCore
import XCTest
@testable import Agentic_Status_Bar

/// Records the commands actions run instead of running them.
private final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(String, [String], String?)] = []

    func run(_ command: String, _ arguments: [String], input: Data?, timeout: TimeInterval?) -> Bool {
        lock.withLock { calls.append((command, arguments, input.map { String(decoding: $0, as: UTF8.self) })) }
        return true
    }

    var recorded: [(String, [String], String?)] { lock.withLock { calls } }
}

/// The store runs the popover's and the notifications' actions with ASBCore's Actions.
@MainActor
final class StoreActionTests: XCTestCase {
    private var home: URL!
    private var stateDir: URL { home.appendingPathComponent(".claude/agentic-status-bar") }
    private let runner = RecordingRunner()

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("asb-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        let state = #"{"v":1,"sessionId":"s1","state":"idle","updatedAt":1,"stateSince":1,"cwd":"/w/web"}"#
        try Data(state.utf8).write(to: stateDir.appendingPathComponent("s1.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func perform(_ name: String, _ args: [String]) {
        let runner = self.runner
        let store = SessionStore(environment: ["HOME": home.path], runner: { _ in runner })
        let finished = expectation(description: name)
        store.perform(name, args) { finished.fulfill() }
        wait(for: [finished], timeout: 5)
    }

    func testMuteFromARowWritesTheMutesFile() throws {
        perform("mute-hour", ["s1"])
        let mutes = try String(contentsOf: stateDir.appendingPathComponent(Mutes.fileName), encoding: .utf8)
        XCTAssertTrue(mutes.contains("/w/web"))
        perform("unmute-all", [])
        XCTAssertFalse(try String(contentsOf: stateDir.appendingPathComponent(Mutes.fileName), encoding: .utf8)
            .contains("/w/web"))
    }

    func testCopyActionsUseTheRunner() {
        perform("copy-cwd", ["s1"])
        XCTAssertEqual(runner.recorded.map(\.0), ["pbcopy"])
        XCTAssertEqual(runner.recorded.first?.2, "/w/web")
    }

    func testUnknownSessionsRunNothing() {
        perform("copy-id", ["nope"])
        perform("focus", ["../s1"])
        XCTAssertTrue(runner.recorded.isEmpty)
    }
}
