import AppKit
import SwiftUI

/// The Settings window, owned by the app rather than a SwiftUI `Settings` scene: macOS 14 ignores
/// `showSettingsWindow:`, and `SettingsLink` needs a scene the popover isn't part of.
@MainActor
final class SettingsWindow {
    private let store: SessionStore
    private let hooks: HookInstaller
    private let login: LoginItem
    private var window: NSWindow?

    init(store: SessionStore, hooks: HookInstaller, login: LoginItem) {
        self.store = store
        self.hooks = hooks
        self.login = login
    }

    /// Opens the window, or brings it to the front; a menu-bar app has to activate itself first.
    func show() {
        let window = self.window ?? make()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, hooks: hooks, login: login)))
        window.title = "Agentic Status Bar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Kept after closing, so reopening is instant and keeps its place.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
