import ServiceManagement
import XCTest
@testable import Agentic_Status_Bar

private final class FakeService: LoginService {
    var status: SMAppService.Status = .notRegistered
    var statusAfterRegister: SMAppService.Status = .enabled
    var error: Error?

    func register() throws {
        if let error { throw error }
        status = statusAfterRegister
    }

    func unregister() throws {
        if let error { throw error }
        status = .notRegistered
    }
}

private struct Failed: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor
final class LoginItemTests: XCTestCase {
    private var agent: String!

    override func setUpWithError() throws {
        agent = FileManager.default.temporaryDirectory.appendingPathComponent("asb-login-\(UUID().uuidString).plist").path
        try Data("<plist/>".utf8).write(to: URL(fileURLWithPath: agent))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: agent)
    }

    func testTurningItOnRegistersAndRemovesTheSwiftBarLaunchAgent() {
        let service = FakeService()
        let login = LoginItem(service: service, oldLaunchAgent: agent)
        XCTAssertFalse(login.enabled)
        login.set(true)
        XCTAssertTrue(login.enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent))
        login.set(false)
        XCTAssertFalse(login.enabled)
    }

    func testApprovalInSystemSettingsCountsAsOnWithAHint() {
        let service = FakeService()
        service.statusAfterRegister = .requiresApproval
        let login = LoginItem(service: service, oldLaunchAgent: agent)
        login.set(true)
        XCTAssertTrue(login.enabled)
        XCTAssertTrue(login.needsApproval)
    }

    func testAFailureIsShownAndChangesNothing() {
        let service = FakeService()
        service.error = Failed()
        let login = LoginItem(service: service, oldLaunchAgent: agent)
        login.set(true)
        XCTAssertFalse(login.enabled)
        XCTAssertEqual(login.failure, "Operation not permitted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent))
    }

    func testRefreshPicksUpChangesMadeInSystemSettings() {
        let service = FakeService()
        let login = LoginItem(service: service, oldLaunchAgent: agent)
        service.status = .enabled
        XCTAssertFalse(login.enabled)
        login.refresh()
        XCTAssertTrue(login.enabled)
    }
}
