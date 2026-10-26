import XCTest
@testable import Agentic_Status_Bar

/// A clock and a scheduler the test advances by hand.
@MainActor
private final class ManualTime {
    var now: TimeInterval = 100
    var scheduled: [(at: TimeInterval, work: @MainActor () -> Void)] = []

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        scheduled.append((now + delay, work))
    }

    /// Moves the clock to `time`, running work that is due, in order.
    func advance(to time: TimeInterval) {
        now = time
        let due = scheduled.filter { $0.at <= time }.sorted { $0.at < $1.at }
        scheduled.removeAll { $0.at <= time }
        for item in due { item.work() }
    }
}

@MainActor
final class CoalescerTests: XCTestCase {
    private func make(_ time: ManualTime, runs: @escaping () -> Void) -> Coalescer {
        Coalescer(interval: 0.2, now: { time.now }, schedule: { time.schedule($0, $1) }, action: runs)
    }

    func testTheFirstTriggerRunsRightAway() {
        let time = ManualTime()
        var runs = 0
        let c = make(time) { runs += 1 }
        c.trigger()
        time.advance(to: 100)
        XCTAssertEqual(runs, 1)
    }

    func testTriggersWhileARunIsScheduledAreFoldedIntoIt() {
        let time = ManualTime()
        var runs = 0
        let c = make(time) { runs += 1 }
        c.trigger()
        c.trigger()
        c.trigger()
        time.advance(to: 100)
        XCTAssertEqual(runs, 1)
    }

    func testRunsAreAtLeastTheIntervalApart() {
        let time = ManualTime()
        var runTimes: [TimeInterval] = []
        let c = make(time) { runTimes.append(time.now) }
        c.trigger()
        time.advance(to: 100)
        time.advance(to: 100.05)
        c.trigger()
        c.trigger()
        time.advance(to: 100.1)
        XCTAssertEqual(runTimes, [100], "a second run before 200 ms have passed")
        time.advance(to: 100.2)
        XCTAssertEqual(runTimes, [100, 100.2])
    }

    func testATriggerLongAfterTheLastRunRunsAtOnce() {
        let time = ManualTime()
        var runs = 0
        let c = make(time) { runs += 1 }
        c.trigger()
        time.advance(to: 100)
        time.advance(to: 105)
        c.trigger()
        time.advance(to: 105)
        XCTAssertEqual(runs, 2)
    }
}
