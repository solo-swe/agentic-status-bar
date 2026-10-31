import AppKit
import ASBCore
import Observation

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

/// Drives the companion from the sessions' state: picks the scene (`CompanionScene`) for each snapshot
/// and plays it, blending through standing between scenes (doc/design/desktop-companion.md).
@MainActor
final class CompanionController {
    let window: CompanionWindow
    private let store: SessionStore
    private var routine: BusyRoutine
    /// The scene playing; nil while the companion is hidden.
    private(set) var scene: CompanionScene?
    private var playedLayout: StripLayout?
    private var watcher: CompanionEnergyWatcher?

    /// Seconds to blend into standing before a new scene.
    static let blend: CFTimeInterval = 0.3

    var figure: StickFigure { window.figure }
    private var layout: StripLayout { window.layout }
    var energy: CompanionEnergy { watcher?.energy ?? CompanionEnergy() }

    private let showSessions: () -> Void
    private let openSettings: () -> Void

    init(
        store: SessionStore, showSessions: @escaping () -> Void = {}, openSettings: @escaping () -> Void = {},
        random: @escaping () -> Double = { .random(in: 0..<1) }
    ) {
        self.store = store
        self.showSessions = showSessions
        self.openSettings = openSettings
        routine = BusyRoutine(random: random)
        window = CompanionWindow(store: store)
        window.onClick = { [weak self] in self?.clicked() }
        window.onRightClick = { [weak self] event, view in self?.showMenu(event, in: view) }
        // Visible until the window server says otherwise (it reports when the panel is covered).
        var initial = CompanionEnergy.current(panel: window.panel)
        initial.visible = true
        watcher = CompanionEnergyWatcher(panel: window.panel, initial: initial) { [weak self] energy in
            self?.energyChanged(energy)
        }
        figure.frameRate = initial.frameRate
        window.onChange = { [weak self] in self?.refresh() }
        refresh()
        observe()
    }

    /// Plays the scene again for the new energy state (or stops it).
    private func energyChanged(_ energy: CompanionEnergy) {
        figure.frameRate = energy.frameRate
        scene = nil
        refresh()
    }

    private func observe() {
        withObservationTracking {
            _ = store.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observe()
            }
        }
    }

    /// Plays the scene for the current snapshot if it changed (or the strip moved to another corner).
    func refresh() {
        guard window.panel.isVisible, energy.shouldAnimate else {
            // Hidden, covered, displays asleep or screen locked: nothing plays, no timers run.
            figure.stop()
            figure.hideProps()
            scene = nil
            return
        }
        let next = CompanionScene.from(store.snapshot)
        figure.setFollowers(Self.followers(next))
        if let scene, scene.sameMoves(as: next), playedLayout == layout {
            self.scene = next
            return
        }
        scene = next
        playedLayout = layout
        figure.hideProps()
        if energy.stillPoses {
            playStill(next)
            return
        }
        figure.animate([figure.presentedPose(), .standing], duration: Self.blend)
        figure.after(Self.blend) { [weak self] in self?.play(next) }
    }

    /// Reduce Motion: one still pose per scene, in its place, no walking.
    private func playStill(_ scene: CompanionScene) {
        figure.stop()
        func place(_ x: CGFloat, facing: StickFigure.Facing) {
            figure.withoutActions { figure.layer.position.x = x }
            figure.facing = facing
        }
        switch scene {
        case .busy:
            let range = layout.walkRange
            place((range.lowerBound + range.upperBound) / 2, facing: .right)
            figure.apply(Moves.weightLifting(figure.skeleton).loop[2])
            figure.show(.barbell)
        case .waiting(let reason):
            figure.apply(Moves.wave(figure.skeleton)[2])
            figure.say(Moves.bubbleGlyph(reason: reason), color: waitingColor())
        case .idle:
            place(layout.restX, facing: layout.bedFacing)
            figure.apply(Moves.lying(figure.skeleton))
            figure.showStillZzz()
        case .none:
            place(layout.restX, facing: layout.bedFacing)
            figure.apply(Moves.sittingOnBed(figure.skeleton))
        case .muted:
            place(layout.restX, facing: layout.bedFacing)
            figure.apply(Moves.reading(figure.skeleton)[0])
            figure.show(.book)
        case .uncertain:
            figure.apply(Moves.scratching(figure.skeleton)[1])
            figure.say(Moves.puzzledGlyph, color: headerColor())
        case .warning:
            figure.apply(Moves.holdingSign(figure.skeleton)[0])
            figure.show(.sign)
        }
    }

    // MARK: Mouse

    /// What a click on the figure does.
    enum ClickTarget: Equatable {
        /// Bring the waiting session's terminal to the front.
        case focus(sessionId: String)
        /// Open the session list.
        case sessions
        /// Open Settings (a warning: usually the hooks).
        case settings
    }

    static func clickTarget(_ snapshot: Snapshot?) -> ClickTarget {
        guard let snapshot else { return .sessions }
        switch snapshot.header.state {
        case .warning:
            return .settings
        case .waiting:
            // The first session waiting on you, if a click can focus it.
            if let waiting = snapshot.sessions.first(where: { $0.shown == .waiting }), waiting.focusable {
                return .focus(sessionId: waiting.sessionId)
            }
            return .sessions
        default:
            return .sessions
        }
    }

    private func clicked() {
        switch Self.clickTarget(store.snapshot) {
        case .focus(let id): store.perform("focus", [id])
        case .sessions: showSessions()
        case .settings: openSettings()
        }
    }

    private func showMenu(_ event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Show Sessions") { [weak self] in self?.showSessions() })
        menu.addItem(ClosureMenuItem("Hide Companion") { [weak self] in self?.store.set("companion", false) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…") { [weak self] in self?.openSettings() })
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// One follower per running subagent while working, up to `StickFigure.maxFollowers`.
    static func followers(_ scene: CompanionScene) -> Int {
        if case .busy(let subagents) = scene { return min(subagents, StickFigure.maxFollowers) }
        return 0
    }

    private func play(_ scene: CompanionScene) {
        figure.hideProps()
        switch scene {
        case .busy:
            nextMove()
        case .waiting(let reason):
            figure.wave(Moves.bubbleGlyph(reason: reason), color: waitingColor())
        case .idle:
            figure.sleep(at: layout.restX, facing: layout.bedFacing)
        case .none:
            figure.sit(at: layout.restX, facing: layout.bedFacing)
        case .muted:
            figure.read(at: layout.restX, facing: layout.bedFacing)
        case .uncertain:
            figure.scratchHead(color: headerColor())
        case .warning:
            figure.holdSign()
        }
    }

    // MARK: Busy routine

    private func nextMove() {
        let (move, seconds) = routine.next()
        let range = layout.walkRange
        guard let activity = move.activity else {
            figure.stroll(for: seconds, in: range, random: routine.random) { [weak self] in self?.rest() }
            return
        }
        // Work out on the free stretch, off the bed.
        let x = figure.presentedX
        let spot = range.contains(x) ? x : range.lowerBound + CGFloat(routine.random()) * (range.upperBound - range.lowerBound)
        figure.walk(to: spot) { [weak self] in
            self?.figure.perform(activity, reps: BusyRoutine.reps(of: activity, in: seconds)) { [weak self] in self?.rest() }
        }
    }

    /// Stands catching its breath for a few seconds, then the next move.
    private func rest() {
        figure.animate(Moves.resting(figure.skeleton), duration: Moves.breath, repeats: true, smooth: true)
        figure.after(routine.rest(longer: energy.lowPower)) { [weak self] in self?.nextMove() }
    }

    /// The theme's waiting color, in the current appearance.
    private func waitingColor() -> CGColor {
        let header = store.snapshot?.header
        let spec = header?.state == .waiting ? header?.color : nil
        return window.resolve(spec.flatMap(ThemeColor.color) ?? .systemRed)
    }

    /// The menu bar's color for its current state (the bubble matches the menu bar), in the current appearance.
    private func headerColor() -> CGColor {
        window.resolve(store.snapshot.flatMap { ThemeColor.color($0.header.color) } ?? .systemGray)
    }
}
