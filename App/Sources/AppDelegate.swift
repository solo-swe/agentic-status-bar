import AppKit
import ASBCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private var statusItem: StatusItemController?
    private lazy var settings = SettingsWindow(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests host the app: keep it quiet then.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        statusItem = StatusItemController(store: store) { [weak self] in self?.settings.show() }
        store.start()
    }
}
