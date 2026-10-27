import AppKit
import ASBCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, MainMenuActions {
    private let store = SessionStore()
    private let hooks = HookInstaller()
    private lazy var login = LoginItem()
    private var statusItem: StatusItemController?
    private lazy var settings = SettingsWindow(store: store, hooks: hooks, login: login, notifier: notifier)
    private lazy var firstRun = FirstRunWindow(hooks: hooks)
    private lazy var notifier = Notifier(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests host the app: keep it quiet then.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        hooks.updateStableCopy()
        NSApp.mainMenu = MainMenu.make(actions: self)
        ActivationPolicy.watch()
        statusItem = StatusItemController(store: store) { [weak self] in self?.settings.show() }
        notifier.start()
        store.start()
        firstRun.showIfNeeded()
        // For checking the window during development: open -a "Agentic Status Bar" --args -ShowSettingsOnLaunch YES
        if UserDefaults.standard.bool(forKey: "ShowSettingsOnLaunch") { settings.show() }
    }

    func showAbout(_ sender: Any?) { AboutPanel.show() }
    func showSettings(_ sender: Any?) { settings.show() }
    func showSessions(_ sender: Any?) { statusItem?.showPopover() }

    /// Clicking the Dock icon (shown while a window is open) brings Settings back if no window is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { settings.show() }
        return true
    }
}
