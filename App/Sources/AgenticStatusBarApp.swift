import SwiftUI

/// Agentic Status Bar: a menu-bar item showing whether any Claude Code agent needs you.
/// The status item lives in AppDelegate; Settings is the only window.
@main
struct AgenticStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A menu-bar app (LSUIElement): the popover's gear button opens this.
        Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}
