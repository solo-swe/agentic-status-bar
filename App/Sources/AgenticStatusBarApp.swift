import SwiftUI

/// Agentic Status Bar: a menu-bar item showing whether any Claude Code agent needs you.
/// It has no windows of its own yet; the status item lives in AppDelegate.
@main
struct AgenticStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A menu-bar app (LSUIElement): Settings is the only scene, added in a later task.
        Settings {
            EmptyView()
        }
    }
}
