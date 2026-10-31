import AppKit
import ASBCore
import Observation

/// The desktop companion's window: a transparent, click-through panel in a corner of the main screen that
/// never takes focus (doc/design/desktop-companion.md › The window). Shown while `companion` is on.
@MainActor
final class CompanionWindow {
    /// The strip the character lives in, in drawing units; on screen it is `scale` times this.
    static let size = NSSize(width: 260, height: 60)
    /// Distance from the screen's left or right edge.
    static let sideMargin: CGFloat = 16

    /// The floor line props and the figure's feet stand on, from the strip's bottom.
    static let floorY: CGFloat = 4

    let panel: NSPanel
    /// The layer the character draws into, in drawing units (`size`), scaled to `companion_size`.
    let contentLayer = CALayer()
    let figure = StickFigure()
    /// How many points on screen a drawing unit takes.
    private(set) var scale: CGFloat = 1
    /// Where the bed is and where the figure may walk, for the current corner.
    private(set) var layout = StripLayout(width: size.width, position: "bottom-right")
    private var bed: CALayer?
    /// Called after the panel was shown, hidden or moved.
    var onChange: (() -> Void)?
    /// A click on the figure, and a right-click (with its event and the view, for a menu).
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var monitors: [Any] = []

    private let store: SessionStore
    private var screenObserver: NSObjectProtocol?

    init(store: SessionStore) {
        self.store = store
        panel = Self.makePanel()
        contentLayer.anchorPoint = .zero
        contentLayer.bounds = CGRect(origin: .zero, size: Self.size)
        contentLayer.position = .zero
        panel.contentView?.layer?.addSublayer(contentLayer)
        figure.layer.position = CGPoint(x: Self.size.width / 2, y: Self.floorY)
        contentLayer.addSublayer(figure.layer)
        if let view = panel.contentView as? CompanionView {
            view.appearanceChanged = { [weak self] view in self?.updateColors(view) }
            view.clicked = { [weak self] in self?.onClick?() }
            view.dragEnded = { [weak self] frame in self?.snap(frame) }
            view.rightClicked = { [weak self, weak view] event in
                if let view { self?.onRightClick?(event, view) }
            }
            updateColors(view)
        }
        watchMouse()
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
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return panel
    }

    /// Strokes in `companion_color`, or the label color of the current appearance (dark on a light desktop,
    /// light on a dark one), with a halo in the opposite brightness around the figure and the bed.
    private func updateColors(_ view: NSView) {
        let chosen = ThemeColor.color(store.config.companionColor) ?? .labelColor
        var color = chosen.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { color = chosen.cgColor }
        let halo = Self.halo(for: color)
        figure.withoutActions {
            figure.color = color
            figure.halo = halo
            if let bed { StickFigure.applyHalo(halo, to: bed) }
        }
    }

    /// White around a dark color, black around a light one.
    static func halo(for color: CGColor) -> CGColor {
        let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let c = rgb?.components ?? [0, 0, 0]
        let luminance = c.count >= 3 ? 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] : c.first ?? 0
        return luminance < 0.5 ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
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
        defer { onChange?() }
        guard config.companion, let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }
        panel.level = Self.level(overFullscreen: config.companionOverFullscreen)
        scale = Self.scale(config.companionSize)
        let size = NSSize(width: Self.size.width * scale, height: Self.size.height * scale)
        panel.setFrame(Self.frame(position: config.companionPosition, in: screen.visibleFrame, size: size), display: false)
        figure.withoutActions { contentLayer.transform = CATransform3DMakeScale(scale, scale, 1) }
        placeBed(StripLayout(width: Self.size.width, position: config.companionPosition))
        if let view = panel.contentView { updateColors(view) }
        panel.orderFrontRegardless()
    }

    /// `color` as it looks in the panel's appearance (light or dark).
    func resolve(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        (panel.contentView?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    /// Draws the bed at the strip's inner end (again when the corner changes).
    func placeBed(_ new: StripLayout) {
        guard bed == nil || new != layout else { return }
        layout = new
        figure.withoutActions {
            bed?.removeFromSuperlayer()
            let layer = figure.makeBed(new)
            layer.position.y += Self.floorY
            StickFigure.applyHalo(figure.halo, to: layer)
            contentLayer.insertSublayer(layer, at: 0)
            bed = layer
        }
    }

    // MARK: Mouse

    /// The panel takes the mouse only while it is over the figure; everywhere else clicks go through. Mouse
    /// monitors need no Accessibility permission (only key monitors do).
    private func watchMouse() {
        panel.acceptsMouseMovedEvents = true
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.hover(NSEvent.mouseLocation) }
        }) { monitors.append(global) }
        // While the panel takes the mouse, its moves come to the app instead.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.hover(NSEvent.mouseLocation) }
            return event
        }) { monitors.append(local) }
    }

    func hover(_ point: NSPoint) {
        guard panel.isVisible, !((panel.contentView as? CompanionView)?.dragging ?? false) else { return }
        let over = isOverFigure(point)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    /// Whether a screen point is on the figure (its hit area, in the panel's scaled drawing).
    func isOverFigure(_ point: NSPoint) -> Bool {
        let frame = panel.frame
        guard frame.contains(point) else { return false }
        let local = CGPoint(x: (point.x - frame.minX) / scale, y: (point.y - frame.minY) / scale)
        return Self.figureRect(x: figure.presentedX, wide: abs(figure.pose.body) > 0.5).contains(local)
    }

    /// The figure's hit area in drawing units around its spot `x`: taller than wide, or wide while it lies
    /// down (in bed, push-ups).
    static func figureRect(x: CGFloat, wide: Bool) -> CGRect {
        let half: CGFloat = wide ? 26 : 14
        return CGRect(x: x - half, y: floorY, width: 2 * half, height: Skeleton.standard.height + 12)
    }

    /// After a drag: the corner nearest the panel's middle becomes `companion_position`, and the panel goes there.
    private func snap(_ frame: NSRect) {
        guard let screen = NSScreen.main else { return }
        let corner = Self.nearestCorner(NSPoint(x: frame.midX, y: frame.midY), in: screen.visibleFrame)
        store.set("companion_position", corner)
        // Back into the corner even when it didn't change.
        update()
    }

    static func nearestCorner(_ point: NSPoint, in visibleFrame: NSRect) -> String {
        let vertical = point.y > visibleFrame.midY ? "top" : "bottom"
        let horizontal = point.x < visibleFrame.midX ? "left" : "right"
        return "\(vertical)-\(horizontal)"
    }

    /// Points on screen per drawing unit for `companion_size`.
    static func scale(_ size: String) -> CGFloat {
        switch size {
        case "small": 1
        case "large": 2
        default: 1.5
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

/// The panel's content view: tells the companion when light or dark mode changes, and about clicks,
/// drags and right-clicks on the figure (the panel only takes the mouse while it is over the figure).
final class CompanionView: NSView {
    var appearanceChanged: ((NSView) -> Void)?
    var clicked: (() -> Void)?
    /// The drag ended with the panel's frame here.
    var dragEnded: ((NSRect) -> Void)?
    var rightClicked: ((NSEvent) -> Void)?
    private(set) var dragging = false
    private var dragStart: NSPoint?
    private var originAtStart: NSPoint?

    /// Points the mouse must move before a press counts as a drag.
    static let dragThreshold: CGFloat = 3

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?(self)
    }

    // The app is never active while you click the figure.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        originAtStart = window?.frame.origin
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = originAtStart, let window else { return }
        let now = NSEvent.mouseLocation
        let (dx, dy) = (now.x - start.x, now.y - start.y)
        if !dragging, hypot(dx, dy) < Self.dragThreshold { return }
        dragging = true
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragging = false
        }
        if dragging, let frame = window?.frame {
            dragEnded?(frame)
        } else {
            clicked?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        rightClicked?(event)
    }
}
