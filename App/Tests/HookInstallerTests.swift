import ASBCore
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class HookInstallerTests: XCTestCase {
    private var home: URL!
    private var asb: String { home.appendingPathComponent("App.app/Contents/Helpers/asb").path }
    private var settings: String { home.appendingPathComponent(".claude/settings.json").path }
    private var stable: String { home.appendingPathComponent("Library/Application Support/agentic-status-bar/bin/asb").path }

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("asb-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            atPath: (asb as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: asb))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func make() -> HookInstaller {
        HookInstaller(environment: ["HOME": home.path], bundledAsb: asb)
    }

    func testInstallAndRemoveTheHooks() throws {
        let hooks = make()
        XCTAssertFalse(hooks.installed)
        hooks.install()
        XCTAssertTrue(hooks.installed)
        XCTAssertNil(hooks.failure)
        XCTAssertEqual(FileManager.default.contents(atPath: stable), FileManager.default.contents(atPath: asb))
        let json = try OrderedJSON.parse(Data(contentsOf: URL(fileURLWithPath: settings)))
        XCTAssertEqual(HookSettings.count(json), HookSettings.events.count)
        XCTAssertTrue(make().installed)
        hooks.uninstall()
        XCTAssertFalse(hooks.installed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stable))
    }

    func testAnInvalidSettingsFileIsLeftAlone() throws {
        try FileManager.default.createDirectory(
            atPath: (settings as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: URL(fileURLWithPath: settings))
        let hooks = make()
        hooks.install()
        XCTAssertFalse(hooks.installed)
        XCTAssertEqual(hooks.failure, "\(settings) isn't valid JSON, so it was left as it is.")
        XCTAssertEqual(FileManager.default.contents(atPath: settings), Data("not json".utf8))
    }

    func testTheStableCopyFollowsTheBundledAsbOnlyWhenInstalled() throws {
        let hooks = make()
        hooks.updateStableCopy()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stable))
        hooks.install()
        try Data("#!/bin/sh\n# newer\n".utf8).write(to: URL(fileURLWithPath: asb))
        hooks.updateStableCopy()
        XCTAssertEqual(FileManager.default.contents(atPath: stable), Data("#!/bin/sh\n# newer\n".utf8))
    }

    func testPathsUnderHomeAreShortened() {
        XCTAssertEqual(FirstRunView.tilde(NSHomeDirectory() + "/.claude/settings.json"), "~/.claude/settings.json")
        XCTAssertEqual(FirstRunView.tilde("/etc/x"), "/etc/x")
    }
}
