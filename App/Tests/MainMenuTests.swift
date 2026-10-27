import AppKit
import XCTest
@testable import Agentic_Status_Bar

@MainActor
private final class RecordingActions: NSObject, MainMenuActions {
    var called: [String] = []
    func showAbout(_ sender: Any?) { called.append("about") }
    func showSettings(_ sender: Any?) { called.append("settings") }
    func showSessions(_ sender: Any?) { called.append("sessions") }
    func checkForUpdates(_ sender: Any?) { called.append("updates") }
}

@MainActor
final class MainMenuTests: XCTestCase {
    func testTheAppMenuHasAboutSettingsSessionsAndQuit() throws {
        let actions = RecordingActions()
        let menu = MainMenu.make(actions: actions)
        XCTAssertEqual(menu.items.map(\.title), ["Agentic Status Bar", "Edit", "Window"])
        let app = try XCTUnwrap(menu.items.first?.submenu)
        let titles = app.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, [
            "About Agentic Status Bar", "Check for Updates…", "Settings…", "Show Sessions", "Hide Agentic Status Bar", "Hide Others",
            "Show All", "Quit Agentic Status Bar",
        ])
        XCTAssertEqual(app.item(withTitle: "Settings…")?.keyEquivalent, ",")
        XCTAssertEqual(app.item(withTitle: "Quit Agentic Status Bar")?.keyEquivalent, "q")
    }

    func testTheOwnItemsReachTheActions() throws {
        let actions = RecordingActions()
        let app = try XCTUnwrap(MainMenu.make(actions: actions).items.first?.submenu)
        for title in ["About Agentic Status Bar", "Check for Updates…", "Settings…", "Show Sessions"] {
            let item = try XCTUnwrap(app.item(withTitle: title))
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        XCTAssertEqual(actions.called, ["about", "updates", "settings", "sessions"])
    }

    func testOnlyMainCapableWindowsKeepTheAppRegular() {
        XCTAssertFalse(ActivationPolicy.needsRegular([]))
        XCTAssertFalse(ActivationPolicy.needsRegular([false, false]))
        XCTAssertTrue(ActivationPolicy.needsRegular([false, true]))
    }
}
