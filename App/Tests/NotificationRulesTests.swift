import ASBCore
import UserNotifications
import XCTest
@testable import Agentic_Status_Bar

final class NotificationRulesTests: XCTestCase {
    private func session(
        _ id: String, _ shown: Snapshot.ShownState, since: Int64, reason: String? = nil, muted: Bool = false,
        focusable: Bool = true, title: String = "fix login"
    ) -> Snapshot.Session {
        Snapshot.Session(
            sessionId: id, project: "web", title: title, shown: shown, reason: reason, since: since, label: "",
            word: "", detail: "", muted: muted, focusable: focusable, symbol: "", color: "")
    }

    private func snapshot(_ sessions: Snapshot.Session...) -> Snapshot {
        Snapshot(generatedAt: 0, header: .init(state: .none, symbol: "", color: ""), sessions: sessions)
    }

    private let defaults = NotificationRules.Options()

    func testAWaitingSessionIsNotifiedOnceAfterTheDelay() {
        var rules = NotificationRules()
        let waiting = snapshot(session("a", .waiting, since: 1000, reason: "permission"))
        var out = rules.evaluate(waiting, now: 5000, options: defaults)
        XCTAssertEqual(out.alerts, [])
        XCTAssertEqual(out.nextDue, 11_000)
        out = rules.evaluate(waiting, now: 11_000, options: defaults)
        XCTAssertEqual(out.alerts, [.init(
            sessionId: "a", kind: .waiting, title: "web — fix login",
            body: "Claude needs your permission to continue.", focusable: true)])
        XCTAssertNil(out.nextDue)
        XCTAssertEqual(rules.evaluate(waiting, now: 60_000, options: defaults).alerts, [])
    }

    func testLeavingTheStateClearsItAndANewStretchNotifiesAgain() {
        var rules = NotificationRules()
        _ = rules.evaluate(snapshot(session("a", .waiting, since: 0)), now: 20_000, options: defaults)
        let busy = rules.evaluate(snapshot(session("a", .busy, since: 21_000)), now: 22_000, options: defaults)
        XCTAssertEqual(busy.cleared, ["a"])
        // Waiting again (even when the busy stretch in between was never seen): a new notification.
        let again = rules.evaluate(snapshot(session("a", .waiting, since: 30_000)), now: 40_000, options: defaults)
        XCTAssertEqual(again.alerts.map(\.sessionId), ["a"])
    }

    func testWaitingBreaksThroughMutesButIdleDoesNot() {
        var options = defaults
        options.idle = true
        var rules = NotificationRules()
        let out = rules.evaluate(snapshot(
            session("w", .waiting, since: 0, muted: true), session("i", .idle, since: 0, muted: true),
            session("j", .idle, since: 0)), now: 20_000, options: options)
        XCTAssertEqual(out.alerts.map(\.sessionId), ["w", "j"])
        XCTAssertEqual(out.alerts.last?.body, "Claude finished and is waiting for your next prompt.")
    }

    func testIdleIsOffByDefaultAndBusyNeverNotifies() {
        var rules = NotificationRules()
        let out = rules.evaluate(snapshot(
            session("i", .idle, since: 0), session("b", .busy, since: 0), session("s", .subagents, since: 0),
            session("u", .uncertain, since: 0)), now: 100_000, options: defaults)
        XCTAssertEqual(out, .init())
    }

    func testAQuestionAndAnUntitledSessionReadWell() {
        let alert = NotificationRules.alert(session("q", .waiting, since: 0, reason: "question", title: ""), kind: .waiting)
        XCTAssertEqual(alert.title, "web")
        XCTAssertEqual(alert.body, "Claude has a question for you.")
    }

    func testAGoneSessionIsClearedAndTheEarliestDueIsNext() {
        var rules = NotificationRules()
        _ = rules.evaluate(snapshot(session("a", .waiting, since: 0)), now: 20_000, options: defaults)
        let out = rules.evaluate(snapshot(
            session("b", .waiting, since: 18_000), session("c", .waiting, since: 15_000)), now: 20_000, options: defaults)
        XCTAssertEqual(out.cleared, ["a"])
        XCTAssertEqual(out.alerts, [])
        XCTAssertEqual(out.nextDue, 25_000)
    }

    func testTurningWaitingOffNotifiesNothing() {
        var options = defaults
        options.waiting = false
        var rules = NotificationRules()
        XCTAssertEqual(rules.evaluate(snapshot(session("a", .waiting, since: 0)), now: 20_000, options: options).alerts, [])
    }

    func testResponsesMapToActions() {
        XCTAssertEqual(Notifier.action(for: UNNotificationDefaultActionIdentifier, focusable: true), "focus")
        XCTAssertNil(Notifier.action(for: UNNotificationDefaultActionIdentifier, focusable: false))
        XCTAssertEqual(Notifier.action(for: Notifier.focusAction, focusable: true), "focus")
        XCTAssertEqual(Notifier.action(for: Notifier.muteAction, focusable: false), "mute-hour")
        XCTAssertNil(Notifier.action(for: UNNotificationDismissActionIdentifier, focusable: true))
    }
}
