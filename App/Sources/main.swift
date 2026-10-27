import AppKit

// Agentic Status Bar: a menu-bar item showing whether any Claude Code agent needs you.
//
// The app starts the AppKit way: AppDelegate owns the status item, the windows and the main menu. A SwiftUI
// `App` would own the main menu instead, and put back its default Help item (AppKit's "Help isn't available")
// whenever one of our SwiftUI windows is in front. SwiftUI views still work inside our AppKit windows.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
