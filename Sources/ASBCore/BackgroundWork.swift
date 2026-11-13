import Foundation

extension HookEvents {
    /// Records the session's background work from a Stop or SubagentStop (doc/state-file-schema.md ›
    /// Background work): `backgroundShells`, each running shell with when it was first seen, and
    /// `wakeupAt`, when the next one-shot scheduled prompt is due. A list the payload doesn't carry
    /// leaves its field as it is. A nil `timeZone` is the hook's own.
    static func recordBackgroundWork(
        _ s: inout [String: Any], payload: HookPayload, now: Int64, timeZone: TimeZone?
    ) {
        if let tasks = payload.backgroundTasks {
            let seen = s["backgroundShells"] as? [String: Any] ?? [:]
            var shells: [String: Any] = [:]
            for task in tasks where task.isRunningShell {
                shells[task.id] = seen[task.id] ?? now
            }
            s["backgroundShells"] = shells.isEmpty ? nil : shells
        }
        if let crons = payload.sessionCrons {
            let oneShots = crons.filter { !$0.recurring }
            let zone = oneShots.isEmpty ? nil : timeZone ?? .current
            s["wakeupAt"] = zone.flatMap { zone in oneShots.compactMap { dueTime($0.schedule, after: now, in: zone) }.min() }
        }
    }

    /// When a one-shot cron line `M H * * *` is next due after `now` (epoch ms), in `timeZone`: today
    /// if that minute hasn't passed yet (a minute that is under way counts as not passed), else
    /// tomorrow. Nil for any other cron line.
    static func dueTime(_ schedule: String, after now: Int64, in timeZone: TimeZone) -> Int64? {
        let fields = schedule.split(separator: " ")
        guard fields.count == 5, fields[2...].allSatisfy({ $0 == "*" }),
              let minute = Int(fields[0]), (0...59).contains(minute),
              let hour = Int(fields[1]), (0...23).contains(hour)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfMinute = Date(timeIntervalSince1970: TimeInterval(now / 60_000 * 60))
        guard let due = calendar.nextDate(
            after: startOfMinute.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
        else { return nil }
        return Int64(due.timeIntervalSince1970 * 1000)
    }
}
