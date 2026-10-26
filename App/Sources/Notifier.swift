import ASBCore
import Foundation
import Observation
import UserNotifications

/// Delivers NotificationRules' alerts through the notification center: asks for permission the
/// first time one is due, offers Focus and Mute project for 1 hour, and focuses the session when the
/// notification is clicked. A notification is withdrawn once its session leaves the state.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let focusCategory = "session-focusable"
    nonisolated static let plainCategory = "session"
    nonisolated static let focusAction = "focus"
    nonisolated static let muteAction = "mute-hour"

    var options = NotificationRules.Options()

    private let store: SessionStore
    private let center = UNUserNotificationCenter.current()
    private var rules = NotificationRules()
    private var timer: Timer?
    private var asked = false

    init(store: SessionStore) {
        self.store = store
        super.init()
        center.delegate = self
        let focus = UNNotificationAction(identifier: Self.focusAction, title: "Focus", options: [.foreground])
        let mute = UNNotificationAction(identifier: Self.muteAction, title: "Mute project for 1 hour")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.focusCategory, actions: [focus, mute], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.plainCategory, actions: [mute], intentIdentifiers: []),
        ])
    }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = store.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.evaluate()
                self?.observe()
            }
        }
    }

    /// Runs the rules on the latest snapshot, now; and again when the next session becomes due.
    func evaluate() {
        guard let snapshot = store.snapshot else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let outcome = rules.evaluate(snapshot, now: now, options: options)
        if !outcome.cleared.isEmpty {
            let ids = outcome.cleared.map(Self.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        if !outcome.alerts.isEmpty { deliver(outcome.alerts) }
        timer?.invalidate()
        timer = outcome.nextDue.map { due in
            Timer.scheduledTimer(withTimeInterval: max(0.1, Double(due - now) / 1000), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        }
    }

    static func identifier(_ sessionId: String) -> String { "asb.\(sessionId)" }

    private func deliver(_ alerts: [NotificationRules.Alert]) {
        let requests = alerts.map { alert in
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.categoryIdentifier = alert.focusable ? Self.focusCategory : Self.plainCategory
            content.userInfo = ["sessionId": alert.sessionId, "focusable": alert.focusable]
            content.threadIdentifier = alert.sessionId
            return UNNotificationRequest(identifier: Self.identifier(alert.sessionId), content: content, trigger: nil)
        }
        let center = self.center
        let send = { for request in requests { center.add(request) } }
        if asked {
            send()
            return
        }
        // Ask on first need; macOS only shows the prompt once.
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.asked = true
                if granted { send() }
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The app is always "in front" as a menu-bar app: show banners anyway.
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let id = info["sessionId"] as? String else { return }
        let focusable = info["focusable"] as? Bool ?? false
        let action = Self.action(for: response.actionIdentifier, focusable: focusable)
        await MainActor.run { [weak self] in
            if let action { self?.store.perform(action, [id]) }
        }
    }

    /// The `Actions` name a notification response runs: clicking it focuses, like the buttons.
    nonisolated static func action(for identifier: String, focusable: Bool) -> String? {
        switch identifier {
        case muteAction: "mute-hour"
        case focusAction, UNNotificationDefaultActionIdentifier: focusable ? "focus" : nil
        default: nil
        }
    }
}
