import ASBCore
import Foundation

/// When to notify: a session that has been waiting on you (or, if turned on, idle) for `delay`
/// gets one notification per stretch in that state. Waiting breaks through mutes, as in the menu
/// bar; idle doesn't. Pure, so the timing rules are unit tested; Notifier delivers.
struct NotificationRules {
    struct Options: Equatable {
        var waiting = true
        var idle = false
        /// How long a session has to stay in the state, in ms.
        var delay: Int64 = 10_000
    }

    /// The options the config file asks for (notify_* keys).
    static func options(_ config: Config) -> Options {
        Options(waiting: config.notifyWaiting, idle: config.notifyIdle, delay: Int64(config.notifyDelaySeconds) * 1000)
    }

    enum Kind: String {
        case waiting, idle
    }

    struct Alert: Equatable {
        var sessionId: String
        var kind: Kind
        var title: String
        var body: String
        var focusable: Bool
    }

    struct Outcome: Equatable {
        var alerts: [Alert] = []
        /// Sessions whose delivered notification is out of date: they left the state, or are gone.
        var cleared: [String] = []
        /// When to evaluate again (epoch ms) for a session not yet due; nil when none is pending.
        var nextDue: Int64?
    }

    /// The stretch each session was notified for: its kind and since when it was in it.
    private(set) var notified: [String: String] = [:]

    mutating func evaluate(_ snapshot: Snapshot, now: Int64, options: Options) -> Outcome {
        var outcome = Outcome()
        var seen: Set<String> = []
        for session in snapshot.sessions {
            seen.insert(session.sessionId)
            let kind = Self.kind(session, options: options)
            let stretch = kind.map { "\($0.rawValue)@\(session.since)" }
            if let old = notified[session.sessionId], old != stretch {
                notified[session.sessionId] = nil
                outcome.cleared.append(session.sessionId)
            }
            guard let kind, let stretch, notified[session.sessionId] == nil else { continue }
            let due = session.since + options.delay
            if now >= due {
                notified[session.sessionId] = stretch
                outcome.alerts.append(Self.alert(session, kind: kind))
            } else {
                outcome.nextDue = min(outcome.nextDue ?? due, due)
            }
        }
        for id in notified.keys where !seen.contains(id) {
            notified[id] = nil
            outcome.cleared.append(id)
        }
        outcome.cleared.sort()
        return outcome
    }

    static func kind(_ s: Snapshot.Session, options: Options) -> Kind? {
        switch s.shown {
        case .waiting where options.waiting: .waiting
        case .idle where options.idle && !s.muted: .idle
        default: nil
        }
    }

    static func alert(_ s: Snapshot.Session, kind: Kind) -> Alert {
        let name = s.title.isEmpty ? s.project : "\(s.project) — \(s.title)"
        let body: String = switch kind {
        case .waiting: s.reason == "question" ? "Claude has a question for you." : "Claude needs your permission to continue."
        case .idle: "Claude finished and is waiting for your next prompt."
        }
        return Alert(sessionId: s.sessionId, kind: kind, title: name, body: body, focusable: s.focusable)
    }
}
