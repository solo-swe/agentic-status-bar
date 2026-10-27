import AppKit
import SwiftUI

/// The Settings window, owned by the app rather than a SwiftUI `Settings` scene: macOS 14 ignores
/// `showSettingsWindow:`, and `SettingsLink` needs a scene the popover isn't part of.
///
/// A toolbar-style tab view controller hosts one SwiftUI view per tab. Each tab reports its content's size,
/// and the tab view controller resizes the window to it on a tab switch: resizing a single hosting
/// controller's window from SwiftUI on a tab switch looped AppKit's layout and crashed.
@MainActor
final class SettingsWindow {
    private let store: SessionStore
    private let hooks: HookInstaller
    private let login: LoginItem
    private let notifier: Notifier
    private let updater: Updater
    private var window: NSWindow?

    init(store: SessionStore, hooks: HookInstaller, login: LoginItem, notifier: Notifier, updater: Updater) {
        self.store = store
        self.hooks = hooks
        self.login = login
        self.notifier = notifier
        self.updater = updater
    }

    /// Opens the window, or brings it to the front; a menu-bar app has to activate itself first.
    func show() {
        let window = self.window ?? make()
        self.window = window
        ActivationPolicy.windowWillShow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab("General", "gearshape", GeneralSettings(store: store, hooks: hooks, login: login, updater: updater)))
        tabs.addTabViewItem(Self.tab("Appearance", "paintpalette", AppearanceSettings(store: store)))
        tabs.addTabViewItem(Self.tab("Notifications", "bell", NotificationSettings(store: store, notifier: notifier)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        // Kept after closing, so reopening is instant and keeps its tab and place.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// One tab: the view at the shared width and its own height, which the window takes when the tab is shown.
    static func tab(_ label: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view.frame(width: SettingsView.width).fixedSize(horizontal: false, vertical: true))
        host.sizingOptions = [.preferredContentSize]
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
