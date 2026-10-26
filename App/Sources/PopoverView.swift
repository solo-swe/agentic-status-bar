import ASBCore
import SwiftUI

/// The popover the status item opens: the session rows, or a placeholder when there are none.
struct PopoverView: View {
    let store: SessionStore
    /// Called after a row was clicked, so the popover can close.
    let didFocus: () -> Void

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
                        SessionRow(item: item) { id in
                            store.perform("focus", [id])
                            didFocus()
                        }
                    }
                }
            } else {
                placeholder
            }
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

    static func invalidNote(_ count: Int) -> String {
        count == 1 ? "1 state file can't be read" : "\(count) state files can't be read"
    }
}
