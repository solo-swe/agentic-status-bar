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

    func testSizesScaleTheWholeStrip() {
        XCTAssertEqual(CompanionWindow.scale("small"), 1)
        XCTAssertEqual(CompanionWindow.scale("medium"), 1.5)
        XCTAssertEqual(CompanionWindow.scale("large"), 2)
        XCTAssertEqual(CompanionWindow.scale("other"), 1.5, "medium by default")
        let big = NSSize(width: CompanionWindow.size.width * 2, height: CompanionWindow.size.height * 2)
        let frame = CompanionWindow.frame(position: "top-left", in: dockBottom, size: big)
        XCTAssertEqual(frame.size, big)
        XCTAssertEqual(frame.maxY, dockBottom.maxY, "still just under the menu bar")
        XCTAssertTrue(dockBottom.contains(frame))
    }

    func testADragSnapsToTheNearestCorner() {
        let screen = dockBottom
        XCTAssertEqual(CompanionWindow.nearestCorner(NSPoint(x: 1300, y: 100), in: screen), "bottom-right")
        XCTAssertEqual(CompanionWindow.nearestCorner(NSPoint(x: 100, y: 100), in: screen), "bottom-left")
        XCTAssertEqual(CompanionWindow.nearestCorner(NSPoint(x: 1300, y: 800), in: screen), "top-right")
        XCTAssertEqual(CompanionWindow.nearestCorner(NSPoint(x: 100, y: 800), in: screen), "top-left")
        XCTAssertEqual(CompanionWindow.nearestCorner(NSPoint(x: 2000, y: 700), in: dockLeft), "top-left", "the second screen's own halves")
        for corner in ["bottom-right", "bottom-left", "top-right", "top-left"] {
            let frame = CompanionWindow.frame(position: corner, in: screen)
            XCTAssertEqual(CompanionWindow.nearestCorner(NSPoint(x: frame.midX, y: frame.midY), in: screen), corner)
        }
    }

    func testTheHitAreaCoversTheFigureOnly() {
        let standing = CompanionWindow.figureRect(x: 100, wide: false)
        XCTAssertTrue(standing.contains(CGPoint(x: 100, y: CompanionWindow.floorY + 20)))
        XCTAssertTrue(standing.contains(CGPoint(x: 100, y: CompanionWindow.floorY + Skeleton.standard.height)), "the head")
        XCTAssertFalse(standing.contains(CGPoint(x: 130, y: 20)), "beside it, clicks go through")
        XCTAssertFalse(standing.contains(CGPoint(x: 100, y: 1)), "below the floor")
        let lying = CompanionWindow.figureRect(x: 100, wide: true)
        XCTAssertTrue(lying.contains(CGPoint(x: 78, y: 14)), "the head on the pillow")
        XCTAssertLessThan(standing.width * 2, CompanionWindow.size.width / 2, "a small part of the strip")
    }

    func testTheViewTellsAClickFromADrag() {
        let view = CompanionView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        XCTAssertTrue(view.acceptsFirstMouse(for: nil), "the app is never active when you click it")
        var clicks = 0
        view.clicked = { clicks += 1 }
        let event = try? XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 0))
        if let event {
            view.mouseDown(with: event)
            view.mouseUp(with: event)
        }
        XCTAssertEqual(clicks, 1)
        XCTAssertFalse(view.dragging)
    }

    func testFullScreenLevelIsOptIn() {
        XCTAssertEqual(CompanionWindow.level(overFullscreen: false), .floating)
        XCTAssertEqual(CompanionWindow.level(overFullscreen: true), .screenSaver)
    }
}
