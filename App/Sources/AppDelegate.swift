import AppKit
import ASBCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A placeholder until the status item controller shows the real header.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agentic Status Bar")
        item.button?.toolTip = "Agentic Status Bar \(ASBVersion.current)"
        statusItem = item
    }
}
