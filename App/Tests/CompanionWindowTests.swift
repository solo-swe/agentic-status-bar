import AppKit
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class CompanionWindowTests: XCTestCase {
    /// A 1440×900 screen with a 25 pt menu bar and a 70 pt Dock at the bottom.
    let dockBottom = NSRect(x: 0, y: 70, width: 1440, height: 805)
    /// A second screen to the right, with the Dock on its left.
    let dockLeft = NSRect(x: 1520, y: 0, width: 1840, height: 1055)

    func testTheStripSitsInTheChosenCorner() {
        let size = CompanionWindow.size
        let cases: [(String, NSRect, NSPoint)] = [
            ("bottom-right", dockBottom, NSPoint(x: 1440 - 16 - size.width, y: 70)),
            ("bottom-left", dockBottom, NSPoint(x: 16, y: 70)),
            ("top-right", dockBottom, NSPoint(x: 1440 - 16 - size.width, y: 875 - size.height)),
            ("top-left", dockBottom, NSPoint(x: 16, y: 875 - size.height)),
            ("bottom-right", dockLeft, NSPoint(x: 3360 - 16 - size.width, y: 0)),
            ("bottom-left", dockLeft, NSPoint(x: 1520 + 16, y: 0)),
            ("top-right", dockLeft, NSPoint(x: 3360 - 16 - size.width, y: 1055 - size.height)),
            ("top-left", dockLeft, NSPoint(x: 1520 + 16, y: 1055 - size.height)),
        ]
        for (position, visible, origin) in cases {
            let frame = CompanionWindow.frame(position: position, in: visible)
            XCTAssertEqual(frame.origin, origin, "\(position) in \(visible)")
            XCTAssertEqual(frame.size, size)
            XCTAssertTrue(visible.contains(frame), "\(position) stays on the screen")
        }
    }

    func testThePanelNeverTakesFocusOrClicks() {
        let panel = CompanionWindow.makePanel()
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeMain, "doesn't turn the app into a regular app (ActivationPolicy)")
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertNotNil(panel.contentView?.layer)
    }

    func testFullScreenLevelIsOptIn() {
        XCTAssertEqual(CompanionWindow.level(overFullscreen: false), .floating)
        XCTAssertEqual(CompanionWindow.level(overFullscreen: true), .screenSaver)
    }
}
