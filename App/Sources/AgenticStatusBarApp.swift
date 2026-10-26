import SwiftUI

/// Agentic Status Bar: a menu-bar item showing whether any Claude Code agent needs you.
/// The status item and the Settings window (SettingsWindow) live in AppDelegate.
@main
struct AgenticStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A SwiftUI App needs a scene; this one is never opened (a menu-bar app has no app menu).
        Settings {
            EmptyView()
        }
    }
}
