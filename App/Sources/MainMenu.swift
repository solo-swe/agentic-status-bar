import AppKit

/// What the app menu's own items do; the app delegate answers them.
@MainActor
@objc protocol MainMenuActions {
    func showAbout(_ sender: Any?)
    func showSettings(_ sender: Any?)
    func showSessions(_ sender: Any?)
    func checkForUpdates(_ sender: Any?)
    func showHelp(_ sender: Any?)
}

/// The menu bar's menus while one of the app's windows is open. A menu-bar app normally has none: while it
/// is an accessory app, the menu bar keeps showing the previous app's menus. `ActivationPolicy` switches the
/// app to a regular app, with these menus and a Dock icon, while a window is open.
@MainActor
enum MainMenu {
    static let appName = "Agentic Status Bar"

    static func make(actions: MainMenuActions) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: appName)
        app.addItem(item("About \(appName)", #selector(MainMenuActions.showAbout(_:)), "", actions))
        app.addItem(item("Check for Updates…", #selector(MainMenuActions.checkForUpdates(_:)), "", actions))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(MainMenuActions.showSettings(_:)), ",", actions))
        app.addItem(item("Show Sessions", #selector(MainMenuActions.showSessions(_:)), "", actions))
        app.addItem(.separator())
        app.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        let others = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
        add(app, to: main)

        // Text fields (a symbol name, for one) need the standard editing commands.
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        let redo = item("Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        add(window, to: main)
        NSApp?.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("\(appName) Help", #selector(MainMenuActions.showHelp(_:)), "?", actions))
        add(help, to: main)
        NSApp?.helpMenu = help

        return main
    }

    /// An item for `action`; without a target it goes up the responder chain.
    private static func item(_ title: String, _ action: Selector, _ key: String, _ target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }
}

/// Makes the app a regular app (menus, Dock icon) while one of its windows is open, and an accessory
/// (menu-bar only) app again when the last one closes.
@MainActor
enum ActivationPolicy {
    /// Call before showing a window.
    static func windowWillShow() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    /// Watches windows closing, and goes back to an accessory app once none of the app's windows is left.
    static func watch() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated {
                // The closing window is still visible here.
                let open = NSApp.windows.filter { $0 !== closing && $0.isVisible }
                if !needsRegular(open.map(\.canBecomeMain)) { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    /// Whether any of the open windows is a document-like one (Settings, first run). The status item,
    /// the popover and the About panel can't become main and don't count.
    static func needsRegular(_ canBecomeMain: [Bool]) -> Bool {
        canBecomeMain.contains(true)
    }
}
