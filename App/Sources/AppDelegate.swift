import AppKit
import ASBCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private let hooks = HookInstaller()
    private lazy var login = LoginItem()
    private var statusItem: StatusItemController?
    private lazy var settings = SettingsWindow(store: store, hooks: hooks, login: login)
    private lazy var firstRun = FirstRunWindow(hooks: hooks)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests host the app: keep it quiet then.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        hooks.updateStableCopy()
        statusItem = StatusItemController(store: store) { [weak self] in self?.settings.show() }
        store.start()
        firstRun.showIfNeeded()
    }
}
