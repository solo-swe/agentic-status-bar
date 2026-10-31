import AppKit
import ASBCore
import Observation

/// The desktop companion's window: a transparent, click-through panel in a corner of the main screen that
/// never takes focus (doc/design/desktop-companion.md › The window). Shown while `companion` is on.
@MainActor
final class CompanionWindow {
    /// The strip the character lives in.
    static let size = NSSize(width: 260, height: 60)
    /// Distance from the screen's left or right edge.
    static let sideMargin: CGFloat = 16

    let panel: NSPanel
    /// The layer the character draws into.
    var contentLayer: CALayer { panel.contentView!.layer! }

    private let store: SessionStore
    private var screenObserver: NSObjectProtocol?

    init(store: SessionStore) {
        self.store = store
        panel = Self.makePanel()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
        observe()
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A shadow would trace the drawn figure.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        panel.contentView = view
        return panel
    }

    private func observe() {
        withObservationTracking {
            _ = store.config
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    /// Shows, places or hides the panel for the current config and screens.
    func update() {
        let config = store.config
        guard config.companion, let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }
        panel.level = Self.level(overFullscreen: config.companionOverFullscreen)
        panel.setFrame(Self.frame(position: config.companionPosition, in: screen.visibleFrame), display: false)
        panel.orderFrontRegardless()
    }

    /// Above normal windows; over full-screen apps only when asked (a floating panel sits below them).
    static func level(overFullscreen: Bool) -> NSWindow.Level {
        overFullscreen ? .screenSaver : .floating
    }

    /// The strip in a corner of `visibleFrame` (the screen minus the menu bar and the Dock): the bottom
    /// corners sit on the Dock (or the screen's bottom), the top ones just under the menu bar.
    static func frame(position: String, in visibleFrame: NSRect, size: NSSize = size) -> NSRect {
        let left = position.hasSuffix("left")
        let top = position.hasPrefix("top")
        let x = left ? visibleFrame.minX + sideMargin : visibleFrame.maxX - sideMargin - size.width
        let y = top ? visibleFrame.maxY - size.height : visibleFrame.minY
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
