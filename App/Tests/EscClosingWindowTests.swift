import AppKit
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class EscClosingWindowTests: XCTestCase {
    func testEscClosesTheWindow() {
        let window = EscClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)
        window.cancelOperation(nil)
        XCTAssertFalse(window.isVisible)
    }
}
