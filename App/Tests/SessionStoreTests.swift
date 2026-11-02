import ASBCore
import XCTest
@testable import Agentic_Status_Bar

/// The store watches the state dir in effect, also after the config moves it.
@MainActor
final class SessionStoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("asb-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testMovingTheStateDirMovesTheWatcher() {
        let store = SessionStore(environment: ["HOME": home.path])
        store.start()
        XCTAssertEqual(store.watchedStateDir, home.appendingPathComponent(".claude/agentic-status-bar").path)

        let moved = home.appendingPathComponent("elsewhere").path
        store.set("state_dir", moved)
        let deadline = Date().addingTimeInterval(5)
        while store.watchedStateDir != moved, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(store.watchedStateDir, moved, "the recompute after the config change moves the watcher")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved), "the new state dir is created, as at start")
    }
}
