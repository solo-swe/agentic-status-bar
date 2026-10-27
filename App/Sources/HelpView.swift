import AppKit
import ASBCore
import SwiftUI

/// What each menu-bar state means, in the order the menu bar picks them.
enum HelpLegend {
    struct Entry: Identifiable {
        var state: String
        var symbol: String
        var color: String
        var meaning: String
        var id: String { state }
    }

    /// The menu bar shows the first of these that applies; the count is the sessions in that state.
    static let order = ["warning", "waiting", "idle", "uncertain", "busy", "subagents", "muted", "none"]

    static let meanings: [String: String] = [
        "warning": "Some state files can't be read. The count is all sessions.",
        "waiting": "A session waits on you: a permission prompt or a question. Shown even for muted projects.",
        "idle": "A session finished its turn and waits for your next prompt.",
        "uncertain": "A working session has gone quiet for longer than the \u{201C}no activity\u{201D} time in Settings.",
        "busy": "Every session is working; nothing needs you.",
        "subagents": "In the list: a session whose turn ended but whose subagents still run. It counts as working.",
        "muted": "Every session is in a muted project. No count.",
        "none": "No Claude Code sessions are running. No count.",
    ]

    /// The legend for the theme in use, overrides included.
    static func entries(_ theme: Theme) -> [Entry] {
        order.map { Entry(state: $0, symbol: theme.symbol($0), color: theme.color($0), meaning: meanings[$0] ?? "") }
    }
}

/// The Help window: how to read the menu bar and the list, and what to do when something looks wrong.
struct HelpView: View {
    let store: SessionStore

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                content.id("top")
            }
            // A link in the text takes the focus when the window opens and scrolls itself into view:
            // go back to the top once the window is up.
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                scroll.scrollTo("top", anchor: .top)
            }
        }
        .frame(width: 560, height: 640)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Getting started") {
                Text("The app shows your Claude Code sessions in the menu bar. It learns about them through Claude Code hooks: install them from the first-run window or **Settings › General**. Sessions that were already running show up after their next event, or when you restart them.")
            }
            section("The menu bar") {
                Text("One symbol for the most urgent state across your sessions, with the number of sessions in that state. The first state in this list that applies wins:")
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(HelpLegend.entries(Theme.resolve(store.config))) { entry in
                        GridRow(alignment: .firstTextBaseline) {
                            Image(systemName: entry.symbol)
                                .foregroundStyle(ThemeColor.color(entry.color).map(Color.init(nsColor:)) ?? .primary)
                                .frame(width: 20)
                            Text(SettingsView.stateName(entry.state)).bold()
                            Text(entry.meaning).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Symbols and colors follow your theme; change them in **Settings › Appearance**. Hovering the menu-bar item says what it shows.")
                    .foregroundStyle(.secondary)
            }
            section("The session list") {
                Text("Click the menu-bar item for every session, most urgent first. A row shows the state's symbol, the project and the session's title, what it's doing (permission, question, idle, working) and how long it has been in that state. Running subagents are listed under their session.")
                Text("Clicking a row brings its terminal pane to the front when the session runs in [herdr](https://herdr.dev). The **…** button (or a right-click) copies the session ID or folder, opens the folder in Finder, reveals the transcript, or mutes the project.")
                Text("At the bottom: **Quit**, ? this Help, ⓘ About, and the gear for Settings.")
            }
            section("Muting a project") {
                Text("**Mute project for 1 hour** or **for today** hides a project's sessions from the menu bar count; they move to the bottom of the list. A muted session that waits on you still turns the menu bar red and still notifies you. Sending a prompt in the project, **Unmute project**, or **Unmute all projects** ends the mute.")
            }
            section("Notifications") {
                Text("When a session has waited on you for a few seconds (10 by default), the app notifies you once; **Focus** jumps to it. **Settings › Notifications** turns them off, adds notifications for idle sessions, and changes the delay and the sound.")
            }
            section("Troubleshooting") {
                bullet("**No sessions show up:** check that the hooks are installed (**Settings › General**), then restart the Claude Code session.")
                bullet("**The warning symbol:** a state file in `~/.claude/agentic-status-bar` can't be read. A running session writes a fresh one on its next event; you can also delete the file.")
                bullet("**A session looks stuck:** sessions that go quiet show as \u{201C}no activity\u{201D} after a while, and ones whose process has exited disappear on the next check.")
                bullet("**No notifications:** allow Agentic Status Bar in **System Settings › Notifications**, then use **Send Test** in **Settings › Notifications**.")
                bullet("**Everything else:** the settings live in `~/.config/agentic-status-bar/config` (**Settings › General › Config file**). More in the [README](https://github.com/hakanserce/agentic-status-bar#readme).")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text)
        }
    }
}

/// The Help window, opened from the Help menu and the ? in the session list.
@MainActor
final class HelpWindow {
    private let store: SessionStore
    private var window: NSWindow?

    init(store: SessionStore) {
        self.store = store
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        ActivationPolicy.windowWillShow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: HelpView(store: store)))
        window.title = "Agentic Status Bar Help"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
