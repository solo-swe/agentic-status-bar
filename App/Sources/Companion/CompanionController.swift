import AppKit
import ASBCore
import Observation

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

    /// Seconds to blend into standing before a new scene.
    static let blend: CFTimeInterval = 0.3

    var figure: StickFigure { window.figure }
    private var layout: StripLayout { window.layout }

    init(store: SessionStore, random: @escaping () -> Double = { .random(in: 0..<1) }) {
        self.store = store
        routine = BusyRoutine(random: random)
        window = CompanionWindow(store: store)
        window.onChange = { [weak self] in self?.refresh() }
        refresh()
        observe()
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
        guard window.panel.isVisible else {
            // Hidden: nothing plays.
            figure.stop()
            figure.hideProps()
            scene = nil
            return
        }
        let next = CompanionScene.from(store.snapshot)
        if let scene, scene.sameMoves(as: next), playedLayout == layout {
            self.scene = next
            return
        }
        scene = next
        playedLayout = layout
        figure.hideProps()
        figure.animate([figure.presentedPose(), .standing], duration: Self.blend)
        figure.after(Self.blend) { [weak self] in self?.play(next) }
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
        case .none, .muted:
            figure.sit(at: layout.restX, facing: layout.bedFacing)
        case .uncertain, .warning:
            figure.apply(.standing)
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
        figure.animate(Moves.resting(figure.skeleton), duration: Moves.breath, repeats: true, fps: nil)
        figure.after(routine.rest()) { [weak self] in self?.nextMove() }
    }

    /// The theme's waiting color, in the current appearance.
    private func waitingColor() -> CGColor {
        let header = store.snapshot?.header
        let spec = header?.state == .waiting ? header?.color : nil
        return window.resolve(spec.flatMap(ThemeColor.color) ?? .systemRed)
    }
}
