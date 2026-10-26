import Foundation

/// Runs an action at most once per `interval`, however often it is triggered: the first trigger runs
/// it (or schedules it for when the interval since the last run is over), and triggers that arrive
/// while a run is scheduled are folded into it.
@MainActor
final class Coalescer {
    let interval: TimeInterval
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let action: () -> Void
    private var lastRun: TimeInterval?
    private var pending = false

    init(
        interval: TimeInterval,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
        },
        action: @escaping () -> Void
    ) {
        self.interval = interval
        self.now = now
        self.schedule = schedule
        self.action = action
    }

    func trigger() {
        guard !pending else { return }
        pending = true
        let wait = lastRun.map { max(0, interval - (now() - $0)) } ?? 0
        schedule(wait) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.lastRun = self.now()
            self.action()
        }
    }
}
