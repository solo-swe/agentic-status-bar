import AppKit
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class AboutPanelTests: XCTestCase {
    func testOptionsCarryTheVersionBuildAndName() {
        let options = AboutPanel.options(Bundle.main)
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(options[.applicationName] as? String, "Agentic Status Bar")
        XCTAssertEqual(options[.applicationVersion] as? String, info["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(options[.version] as? String, info["CFBundleVersion"] as? String)
    }

    func testCreditsLinkToTheRepository() {
        let credits = AboutPanel.credits()
        let range = (credits.string as NSString).range(of: "github.com/hakanserce/agentic-status-bar")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(credits.attribute(.link, at: range.location, effectiveRange: nil) as? URL, AboutPanel.projectURL)
    }
}
