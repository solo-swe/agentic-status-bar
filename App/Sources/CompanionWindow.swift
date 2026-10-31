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

    /// The floor line props and the figure's feet stand on, from the strip's bottom.
    static let floorY: CGFloat = 4

    let panel: NSPanel
    /// The layer the character draws into.
    var contentLayer: CALayer { panel.contentView!.layer! }
    let figure = StickFigure()
    /// Where the bed is and where the figure may walk, for the current corner.
    private(set) var layout = StripLayout(width: size.width, position: "bottom-right")
    private var bed: CALayer?

    private let store: SessionStore
    private var screenObserver: NSObjectProtocol?

    init(store: SessionStore) {
        self.store = store
        panel = Self.makePanel()
        figure.layer.position = CGPoint(x: Self.size.width / 2, y: Self.floorY)
        contentLayer.addSublayer(figure.layer)
        if let view = panel.contentView as? CompanionView {
            view.appearanceChanged = { [weak self] view in self?.updateColors(view) }
            updateColors(view)
        }
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
        let view = CompanionView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        panel.contentView = view
        return panel
    }

    /// Strokes in the label color of the current appearance: dark on a light desktop, light on a dark one.
    private func updateColors(_ view: NSView) {
        var color = NSColor.labelColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.cgColor }
        figure.withoutActions { figure.color = color }
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
        placeBed(StripLayout(width: Self.size.width, position: config.companionPosition))
        panel.orderFrontRegardless()
    }

    /// Draws the bed at the strip's inner end (again when the corner changes).
    func placeBed(_ new: StripLayout) {
        guard bed == nil || new != layout else { return }
        layout = new
        figure.withoutActions {
            bed?.removeFromSuperlayer()
            let layer = figure.makeBed(new)
            layer.position.y += Self.floorY
            contentLayer.insertSublayer(layer, at: 0)
            bed = layer
        }
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

/// The panel's content view: tells the companion when light or dark mode changes.
final class CompanionView: NSView {
    var appearanceChanged: ((NSView) -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?(self)
    }
}
