import ASBCore
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class StatusItemTests: XCTestCase {
    func testHexColorsParse() throws {
        let red = try XCTUnwrap(ThemeColor.hex("#FF0000"))
        XCTAssertEqual(red.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(red.greenComponent, 0, accuracy: 0.001)
        XCTAssertNil(ThemeColor.hex("red"))
        XCTAssertNil(ThemeColor.hex("#12345"))
        XCTAssertNil(ThemeColor.color("#FF0000,#00FF00,#0000FF"))
    }

    func testAPairFollowsTheAppearance() throws {
        let color = try XCTUnwrap(ThemeColor.color("#B25000,#FFD60A"))
        var light: NSColor?
        var dark: NSColor?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { light = color.usingColorSpace(.sRGB) }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { dark = color.usingColorSpace(.sRGB) }
        XCTAssertEqual(try XCTUnwrap(light).blueComponent, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dark).blueComponent, 10.0 / 255, accuracy: 0.001)
    }

    func testThePresentationShowsTheSymbolAndCount() {
        let p = StatusItemController.presentation(.init(state: .idle, symbol: "zzz", color: "#B25000,#FFD60A", count: 2))
        XCTAssertEqual(p.symbol, "zzz")
        XCTAssertEqual(p.title, "\u{2009}2")
        XCTAssertNotNil(p.color)
        XCTAssertEqual(p.toolTip, "Agentic Status Bar: 2 idle")
    }

    func testNoCountMeansNoTitle() {
        let p = StatusItemController.presentation(.init(state: .muted, symbol: "bell.slash", color: "#8E8E93,#98989D"))
        XCTAssertEqual(p.title, "")
        XCTAssertEqual(p.toolTip, "Agentic Status Bar: All sessions muted")
    }

    func testSymbolsAreDrawnInColorNotAsTemplates() throws {
        let colored = try XCTUnwrap(ThemeColor.symbol("zzz", color: ThemeColor.color("#B25000")))
        XCTAssertFalse(colored.isTemplate)
        let plain = try XCTUnwrap(ThemeColor.symbol("zzz", color: nil))
        XCTAssertTrue(plain.isTemplate)
        XCTAssertNil(ThemeColor.symbol("no.such.symbol.xyz", color: nil))
    }
}
