import ASBCore
import SwiftUI

/// The popover the status item opens: the session rows, or a placeholder when there are none.
struct PopoverView: View {
    let store: SessionStore
    /// Closes the popover (after an action that brings another app to the front).
    let close: () -> Void
    let openSettings: () -> Void
    let openHelp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let snapshot = store.snapshot {
                if snapshot.invalidFiles > 0 {
                    Label(Self.invalidNote(snapshot.invalidFiles), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                }
                let rows = RowItem.rows(snapshot)
                if rows.isEmpty {
                    placeholder
                } else {
                    ForEach(rows) { item in
                        SessionRow(item: item, perform: perform)
                    }
                }
                if snapshot.activeMutes > 0 {
                    Divider().padding(.vertical, 2)
                    Button("Unmute all projects") { perform("unmute-all", []) }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                }
            } else {
                placeholder
            }
            Divider().padding(.vertical, 2)
            HStack {
                // A menu-bar app has no Dock icon or app menu: this is the only way to quit it.
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
                    .help("Quit Agentic Status Bar")
                Spacer()
                Button {
                    close()
                    openHelp()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Agentic Status Bar Help")
                Button {
                    close()
                    AboutPanel.show()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("About Agentic Status Bar")
                Button {
                    close()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
        }
        .padding(6)
        .frame(width: 420, alignment: .leading)
    }

    private var placeholder: some View {
        Text("No Claude Code sessions")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
    }

    /// Actions that switch to another app; the popover closes for them and stays open for the rest,
    /// so a mute shows up in place.
    static let closingActions: Set = ["focus", "open-folder", "reveal-transcript"]

    private func perform(_ action: String, _ args: [String]) {
        store.perform(action, args)
        if Self.closingActions.contains(action) { close() }
    }

    static func invalidNote(_ count: Int) -> String {
        count == 1 ? "1 state file can't be read" : "\(count) state files can't be read"
    }
}
