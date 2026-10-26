import ASBCore
import XCTest
@testable import Agentic_Status_Bar

final class SettingsTests: XCTestCase {
    func testColorsRoundTripThroughHex() throws {
        let (light, dark) = try XCTUnwrap(ThemeColor.halves("#B25000,#FFD60A"))
        XCTAssertEqual(SettingsView.colorSetting(light: light, dark: dark), "#B25000,#FFD60A")
        let single = try XCTUnwrap(ThemeColor.halves("#123456"))
        XCTAssertEqual(ThemeColor.hexString(single.dark), "#123456")
        XCTAssertNil(ThemeColor.halves("#12345"))
    }

    func testTheWrittenColorIsValidConfig() throws {
        let value = try XCTUnwrap(SettingsView.colorSetting(light: .systemRed, dark: .systemBlue))
        XCTAssertTrue(Config.isValid(value, for: "color_idle"))
    }

    func testTheChoicesMatchWhatTheCLIAccepts() {
        XCTAssertEqual(Set(SettingsView.staleChoices.map { String($0.minutes) }), Actions.settable["stale_minutes"])
        XCTAssertEqual(Set(SettingsView.themes), Actions.settable["theme"])
        XCTAssertEqual(Set(SettingsView.themes), Set(Theme.builtIn.keys))
    }

    func testNotificationOptionsComeFromTheConfig() {
        XCTAssertEqual(NotificationRules.options(Config()), NotificationRules.Options())
        let config = Config.parse("notify_waiting=0\nnotify_idle=1\nnotify_delay_seconds=30\n")
        XCTAssertEqual(NotificationRules.options(config), .init(waiting: false, idle: true, delay: 30_000))
        XCTAssertTrue(SettingsView.delayChoices.contains(Config().notifyDelaySeconds))
        XCTAssertTrue(SettingsView.delayChoices.allSatisfy { Config.isValid(String($0), for: "notify_delay_seconds") })
    }

    func testNames() {
        XCTAssertEqual(SettingsView.themeName("high_contrast"), "High contrast")
        XCTAssertEqual(SettingsView.themeName("monochrome"), "Monochrome")
        XCTAssertEqual(SettingsView.stateName("uncertain"), "No activity")
        XCTAssertEqual(SettingsView.stateName("waiting"), "Waiting")
    }

    func testSymbolNamesAreChecked() {
        XCTAssertTrue(StateOverrideRow.isSymbol("zzz"))
        XCTAssertFalse(StateOverrideRow.isSymbol("no.such.symbol.xyz"))
        XCTAssertFalse(StateOverrideRow.isSymbol(""))
    }
}
