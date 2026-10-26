import ASBCore
import SwiftUI

/// One line of the popover: a session, or a subagent indented under its session.
struct RowItem: Identifiable, Equatable {
    var id: String
    var symbol: String
    var color: String
    var text: String
    var word: String
    var detail: String
    var indented = false
    var muted = false
    /// The session a click focuses; nil when it can't be focused.
    var focusId: String?

    /// The popover's rows in snapshot order, each session followed by its subagents.
    static func rows(_ snapshot: Snapshot, subagentSymbol: String = "arrow.turn.down.right") -> [RowItem] {
        snapshot.sessions.flatMap { s -> [RowItem] in
            let session = RowItem(
                id: s.sessionId, symbol: s.symbol, color: s.color,
                text: s.title.isEmpty ? s.project : "\(s.project) — \(s.title)",
                word: s.word, detail: s.detail, muted: s.muted, focusId: s.focusable ? s.sessionId : nil)
            let subagents = s.subagents.map { a in
                RowItem(
                    id: "\(s.sessionId)/\(a.id)", symbol: subagentSymbol, color: s.color, text: a.type,
                    word: "", detail: a.detail, indented: true, muted: s.muted, focusId: session.focusId)
            }
            return [session] + subagents
        }
    }
}

struct SessionRow: View {
    let item: RowItem
    let focus: (String) -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.symbol)
                .foregroundStyle(ThemeColor.color(item.color).map(Color.init(nsColor:)) ?? .secondary)
                .frame(width: 16)
            Text(item.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(item.muted ? .secondary : .primary)
            Spacer(minLength: 12)
            if !item.word.isEmpty {
                Text(item.word).foregroundStyle(.secondary)
            }
            Text(item.detail)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(item.indented ? .callout : .body)
        .padding(.leading, item.indented ? 22 : 0)
        .padding(.horizontal, 8)
        .frame(height: item.indented ? 20 : 22)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(hovered && item.focusId != nil ? Color.accentColor.opacity(0.2) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { if let id = item.focusId { focus(id) } }
        .help(item.focusId != nil ? "Click to focus this session" : "")
    }
}
