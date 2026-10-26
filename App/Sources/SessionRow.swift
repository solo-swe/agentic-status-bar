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
    /// What the row's menu offers; empty for subagent rows.
    var actions: [RowAction] = []

    /// The popover's rows in snapshot order, each session followed by its subagents.
    static func rows(_ snapshot: Snapshot, subagentSymbol: String = "arrow.turn.down.right") -> [RowItem] {
        snapshot.sessions.flatMap { s -> [RowItem] in
            let session = RowItem(
                id: s.sessionId, symbol: s.symbol, color: s.color,
                text: s.title.isEmpty ? s.project : "\(s.project) — \(s.title)",
                word: s.word, detail: s.detail, muted: s.muted, focusId: s.focusable ? s.sessionId : nil,
                actions: RowAction.menu(for: s))
            let subagents = s.subagents.map { a in
                RowItem(
                    id: "\(s.sessionId)/\(a.id)", symbol: subagentSymbol, color: s.color, text: a.type,
                    word: "", detail: a.detail, indented: true, muted: s.muted, focusId: session.focusId)
            }
            return [session] + subagents
        }
    }
}

/// An entry of a session row's menu, run as the `Actions` action of the same name.
struct RowAction: Identifiable, Equatable {
    var title: String
    var action: String
    var sessionId: String
    /// A divider goes before this entry.
    var startsGroup = false

    var id: String { action }

    static func menu(for s: Snapshot.Session) -> [RowAction] {
        let id = s.sessionId
        var items: [RowAction] = []
        if s.focusable { items.append(.init(title: "Focus", action: "focus", sessionId: id)) }
        if s.muted {
            items.append(.init(title: "Unmute project", action: "unmute", sessionId: id, startsGroup: !items.isEmpty))
        } else {
            items.append(.init(title: "Mute project for 1 hour", action: "mute-hour", sessionId: id, startsGroup: !items.isEmpty))
            items.append(.init(title: "Mute project for today", action: "mute-today", sessionId: id))
        }
        items.append(.init(title: "Copy session ID", action: "copy-id", sessionId: id, startsGroup: true))
        if s.cwd?.isEmpty == false {
            items.append(.init(title: "Copy working directory", action: "copy-cwd", sessionId: id))
            items.append(.init(title: "Open folder in Finder", action: "open-folder", sessionId: id, startsGroup: true))
        }
        if s.transcriptPath?.isEmpty == false {
            items.append(.init(
                title: "Reveal transcript", action: "reveal-transcript", sessionId: id,
                startsGroup: s.cwd?.isEmpty != false))
        }
        return items
    }
}

struct SessionRow: View {
    let item: RowItem
    let perform: (String, [String]) -> Void
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
            if !item.actions.isEmpty {
                Menu { menuItems } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .opacity(hovered ? 1 : 0)
                    .help("More actions")
            }
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
        .onTapGesture { if let id = item.focusId { perform("focus", [id]) } }
        .contextMenu { menuItems }
        .help(item.focusId != nil ? "Click to focus this session" : "")
    }

    @ViewBuilder private var menuItems: some View {
        ForEach(item.actions) { entry in
            if entry.startsGroup { Divider() }
            Button(entry.title) { perform(entry.action, [entry.sessionId]) }
        }
    }
}
