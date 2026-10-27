import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class UpdaterTests: XCTestCase {
    private let release: [String: Any] = ["SUPublicEDKey": "abc=", "SUFeedURL": "https://example.com/appcast.xml"]

    func testOnlyBuildsWithAKeyAndAFeedUpdate() {
        XCTAssertTrue(Updater.canUpdate(release, environment: [:]))
        XCTAssertFalse(Updater.canUpdate(["SUPublicEDKey": "", "SUFeedURL": "https://example.com/a.xml"], environment: [:]))
        XCTAssertFalse(Updater.canUpdate(["SUPublicEDKey": "abc="], environment: [:]))
    }

    func testUnitTestsNeverUpdate() {
        XCTAssertFalse(Updater.canUpdate(release, environment: ["XCTestConfigurationFilePath": "/x"]))
    }
}
