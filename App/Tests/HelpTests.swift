import ASBCore
import XCTest
@testable import Agentic_Status_Bar

final class HelpTests: XCTestCase {
    func testTheLegendExplainsEveryThemeState() {
        XCTAssertEqual(Set(HelpLegend.order), Set(Config.themeStates))
        XCTAssertEqual(HelpLegend.order.count, Config.themeStates.count)
        for state in Config.themeStates {
            XCTAssertFalse(HelpLegend.meanings[state, default: ""].isEmpty, state)
        }
    }

    func testTheLegendUsesTheThemeInUse() {
        let config = Config.parse("theme=high_contrast\nicon_idle=moon.fill\n")
        let entries = HelpLegend.entries(Theme.resolve(config))
        XCTAssertEqual(entries.first { $0.state == "idle" }?.symbol, "moon.fill")
        XCTAssertEqual(entries.first { $0.state == "waiting" }?.symbol, "exclamationmark.octagon.fill")
    }
}
