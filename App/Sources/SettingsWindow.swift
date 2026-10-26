import AppKit
import SwiftUI

/// The Settings window, owned by the app rather than a SwiftUI `Settings` scene: macOS 14 ignores
/// `showSettingsWindow:`, and `SettingsLink` needs a scene the popover isn't part of.
@MainActor
final class SettingsWindow {
    private let store: SessionStore
    private var window: NSWindow?

    init(store: SessionStore) {
        self.store = store
    }

    /// Opens the window, or brings it to the front; a menu-bar app has to activate itself first.
    func show() {
        let window = self.window ?? make()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(store: store))
        // The window follows the selected tab's size.
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Agentic Status Bar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Kept after closing, so reopening is instant and keeps its place.
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
