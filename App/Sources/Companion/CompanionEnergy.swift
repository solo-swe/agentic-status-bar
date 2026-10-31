import AppKit

/// When the companion may move, and how much (doc/design/desktop-companion.md › Energy and etiquette):
/// nothing at all while it can't be seen, slower in Low Power Mode, still poses with Reduce Motion.
struct CompanionEnergy: Equatable {
    /// Some of the panel is on screen (not covered, not on another Space).
    var visible = true
    var displaysAsleep = false
    var screenLocked = false
    var lowPower = false
    var reduceMotion = false

    /// Whether anything should play: while it can't be seen, the companion stops completely (no
    /// animations, no timers) and picks up its scene again when it can.
    var shouldAnimate: Bool { visible && !displaysAsleep && !screenLocked }

    /// Still frames a second for moves.
    var frameRate: Double { lowPower ? 6 : 12 }

    /// One still pose per scene, swapped when the scene changes.
    var stillPoses: Bool { reduceMotion }

    /// The current system state.
    @MainActor
    static func current(panel: NSWindow) -> CompanionEnergy {
        CompanionEnergy(
            visible: panel.occlusionState.contains(.visible), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

/// Watches what `CompanionEnergy` depends on and reports every change. The notification centers are
/// injectable for tests.
@MainActor
final class CompanionEnergyWatcher {
    private(set) var energy: CompanionEnergy
    private let changed: (CompanionEnergy) -> Void
    /// The observers, kept for the app's lifetime (they hold the watcher weakly).
    private var tokens: [NSObjectProtocol] = []

    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    init(
        panel: NSWindow, initial: CompanionEnergy, center: NotificationCenter = .default,
        workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributed: NotificationCenter = DistributedNotificationCenter.default(),
        changed: @escaping (CompanionEnergy) -> Void
    ) {
        energy = initial
        self.changed = changed
        watch(center, NSWindow.didChangeOcclusionStateNotification, object: panel) { [weak panel] e in
            e.visible = panel?.occlusionState.contains(.visible) ?? false
        }
        watch(center, .NSProcessInfoPowerStateDidChange) { e in e.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { e in e.displaysAsleep = true }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { e in e.displaysAsleep = false }
        watch(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { e in
            e.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        watch(distributed, Self.screenLocked) { e in e.screenLocked = true }
        watch(distributed, Self.screenUnlocked) { e in e.screenLocked = false }
    }

    private func watch(
        _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
        _ update: @escaping @MainActor (inout CompanionEnergy) -> Void
    ) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(update) }
        }
        tokens.append(token)
    }

    /// Applies a change, reporting it only when something changed.
    func apply(_ update: (inout CompanionEnergy) -> Void) {
        var next = energy
        update(&next)
        guard next != energy else { return }
        energy = next
        changed(next)
    }
}
