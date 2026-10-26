import AppKit
import ASBCore
import Observation
import SwiftUI

/// The menu-bar item: the header's symbol in its theme color, and the count next to it in the same
/// color. Updates whenever the store publishes a snapshot.
@MainActor
final class StatusItemController {
    let item: NSStatusItem
    private let store: SessionStore

    private let popover = NSPopover()

    init(store: SessionStore) {
        self.store = store
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        // Closes on a click outside it.
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store) { [weak popover] in popover?.performClose(nil) })
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        update()
        observe()
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func observe() {
        withObservationTracking {
            _ = store.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    func update() {
        guard let button = item.button else { return }
        let header = store.snapshot?.header
            ?? Snapshot.Header(state: .none, symbol: "sparkle", color: "#C7C7CC,#48484A")
        let presentation = Self.presentation(header)
        button.image = ThemeColor.symbol(presentation.symbol, color: presentation.color)
        button.attributedTitle = NSAttributedString(
            string: presentation.title,
            attributes: [
                .foregroundColor: presentation.color ?? NSColor.labelColor,
                .font: NSFont.menuBarFont(ofSize: 0),
            ])
        button.toolTip = presentation.toolTip
        button.setAccessibilityLabel(presentation.toolTip)
    }

    struct Presentation {
        var symbol: String
        var color: NSColor?
        /// The count, with a thin space before it; "" when there is none.
        var title: String
        var toolTip: String
    }

    static func presentation(_ header: Snapshot.Header) -> Presentation {
        let count = header.count.map { "\u{2009}\($0)" } ?? ""
        let what: String = switch header.state {
        case .warning: "Some state files can't be read"
        case .waiting: "\(header.count ?? 0) waiting on you"
        case .idle: "\(header.count ?? 0) idle"
        case .uncertain: "\(header.count ?? 0) with no recent activity"
        case .busy: "\(header.count ?? 0) working"
        case .muted: "All sessions muted"
        case .none: "No Claude Code sessions"
        }
        return Presentation(
            symbol: header.symbol, color: ThemeColor.color(header.color), title: count,
            toolTip: "Agentic Status Bar: \(what)")
    }
}
