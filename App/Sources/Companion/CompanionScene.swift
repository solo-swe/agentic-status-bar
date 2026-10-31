import ASBCore
import Foundation

/// What the companion acts out (doc/design/desktop-companion.md › State → animation): the menu bar's
/// header state, so the two always agree (idle outranks busy there too).
enum CompanionScene: Equatable {
    case warning
    /// A session waits on you: `permission` or `question`.
    case waiting(reason: String?)
    /// Sessions are working, with this many subagents running.
    case busy(subagents: Int)
    case uncertain
    case idle
    /// Only muted sessions.
    case muted
    /// No sessions.
    case none

    static func from(_ snapshot: Snapshot?) -> CompanionScene {
        guard let snapshot else { return .none }
        let loud = snapshot.sessions.filter { !$0.muted }
        switch snapshot.header.state {
        case .warning: return .warning
        case .waiting:
            // Rows come most urgent first; the reason of the first session waiting on you.
            return .waiting(reason: loud.first { $0.shown == .waiting }?.reason)
        case .idle: return .idle
        case .uncertain: return .uncertain
        case .busy:
            let working = loud.filter { $0.shown == .busy || $0.shown == .subagents }
            return .busy(subagents: working.reduce(0) { $0 + $1.subagents.count })
        case .muted: return .muted
        case .none: return .none
        }
    }

    /// Scenes that play the same moves: a new subagent doesn't restart the routine.
    func sameMoves(as other: CompanionScene) -> Bool {
        switch (self, other) {
        case (.busy, .busy): true
        default: self == other
        }
    }
}

/// The calm busy routine: one activity for a while, a rest, then a different one
/// (doc/design/desktop-companion.md › Busy routine).
struct BusyRoutine {
    enum Move: CaseIterable, Equatable {
        case walk, weightLifting, pushUps, jumpingJacks, pullUps

        /// The figure's activity for a workout; nil for walking (a stroll, not a loop in place).
        var activity: Activity? {
            switch self {
            case .walk: nil
            case .weightLifting: Moves.weightLifting()
            case .pushUps: Moves.pushUps()
            case .jumpingJacks: Moves.jumpingJacks()
            case .pullUps: Moves.pullUps()
            }
        }
    }

    static let activitySeconds: ClosedRange<Double> = 8...15
    static let restSeconds: ClosedRange<Double> = 4...8

    /// Gives numbers in 0..<1.
    var random: () -> Double
    private(set) var last: Move?

    init(random: @escaping () -> Double = { .random(in: 0..<1) }) {
        self.random = random
    }

    /// The next move, never the same as the last one, and how long to do it.
    mutating func next() -> (Move, seconds: Double) {
        let choices = Move.allCases.filter { $0 != last }
        let move = choices[min(Int(random() * Double(choices.count)), choices.count - 1)]
        last = move
        return (move, pick(Self.activitySeconds))
    }

    /// How long to rest after an activity; `longer` (Low Power Mode) doubles it.
    func rest(longer: Bool = false) -> Double {
        pick(Self.restSeconds) * (longer ? 2 : 1)
    }

    private func pick(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + random() * (range.upperBound - range.lowerBound)
    }

    /// Whole reps of `activity` that fit in about `seconds`, at least one.
    static func reps(of activity: Activity, in seconds: Double) -> Int {
        max(1, Int(((seconds - activity.introDuration - activity.outroDuration) / activity.rep).rounded()))
    }
}
