import ASBCore
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class CompanionSceneTests: XCTestCase {
    func session(
        _ shown: Snapshot.ShownState, reason: String? = nil, muted: Bool = false, subagents: Int = 0
    ) -> Snapshot.Session {
        Snapshot.Session(
            sessionId: UUID().uuidString, project: "api", shown: shown, reason: reason, since: 0, label: "api",
            word: "", detail: "", muted: muted, symbol: "", color: "",
            subagents: (0..<subagents).map { Snapshot.Subagent(id: "\($0)", type: "agent", since: 0, detail: "") })
    }

    func snapshot(_ state: Snapshot.HeaderState, _ sessions: [Snapshot.Session]) -> Snapshot {
        Snapshot(generatedAt: 0, header: .init(state: state, symbol: "", color: ""), sessions: sessions)
    }

    func testEveryHeaderStateHasAScene() {
        XCTAssertEqual(CompanionScene.from(nil), .none)
        XCTAssertEqual(CompanionScene.from(snapshot(.none, [])), .none)
        XCTAssertEqual(CompanionScene.from(snapshot(.warning, [session(.busy)])), .warning)
        XCTAssertEqual(CompanionScene.from(snapshot(.waiting, [session(.waiting, reason: "question")])), .waiting(reason: "question"))
        XCTAssertEqual(CompanionScene.from(snapshot(.waiting, [session(.waiting, reason: "permission")])), .waiting(reason: "permission"))
        XCTAssertEqual(CompanionScene.from(snapshot(.busy, [session(.busy)])), .busy(subagents: 0))
        XCTAssertEqual(CompanionScene.from(snapshot(.busy, [session(.subagents, subagents: 2)])), .busy(subagents: 2))
        XCTAssertEqual(CompanionScene.from(snapshot(.uncertain, [session(.uncertain)])), .uncertain)
        XCTAssertEqual(CompanionScene.from(snapshot(.idle, [session(.idle)])), .idle)
        XCTAssertEqual(CompanionScene.from(snapshot(.muted, [session(.busy, muted: true)])), .muted)
    }

    func testItFollowsTheMenuBarWithSeveralSessions() {
        // Idle outranks busy in the menu bar, and so here: two idle sessions and a busy one sleep.
        XCTAssertEqual(CompanionScene.from(snapshot(.idle, [session(.idle), session(.idle), session(.busy)])), .idle)
        XCTAssertEqual(CompanionScene.from(snapshot(.uncertain, [session(.uncertain), session(.busy)])), .uncertain)
        XCTAssertEqual(
            CompanionScene.from(snapshot(.waiting, [session(.waiting, reason: "question"), session(.idle)])),
            .waiting(reason: "question"))
        // Muted sessions don't count toward subagents; subagents of all working sessions do.
        XCTAssertEqual(
            CompanionScene.from(snapshot(.busy, [
                session(.busy, subagents: 1), session(.subagents, subagents: 2), session(.busy, muted: true, subagents: 4),
            ])),
            .busy(subagents: 3))
    }

    func testANewSubagentDoesNotRestartTheRoutine() {
        XCTAssertTrue(CompanionScene.busy(subagents: 0).sameMoves(as: .busy(subagents: 2)))
        XCTAssertFalse(CompanionScene.busy(subagents: 0).sameMoves(as: .idle))
        XCTAssertFalse(CompanionScene.waiting(reason: "permission").sameMoves(as: .waiting(reason: "question")))
    }

    func testTheRoutineNeverRepeatsAndStaysInRange() {
        // A seeded linear congruential generator: the same sequence every run.
        var state: UInt64 = 42
        var routine = BusyRoutine(random: {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        })
        var last: BusyRoutine.Move?
        var seen = Set<String>()
        for _ in 0..<40 {
            let (move, seconds) = routine.next()
            XCTAssertNotEqual(move, last)
            XCTAssertTrue(BusyRoutine.activitySeconds.contains(seconds))
            XCTAssertTrue(BusyRoutine.restSeconds.contains(routine.rest()))
            XCTAssertEqual(routine.rest(longer: true) >= BusyRoutine.restSeconds.lowerBound * 2, true)
            seen.insert("\(move)")
            last = move
        }
        XCTAssertEqual(seen.count, BusyRoutine.Move.allCases.count, "every move comes up")
        // Even a source stuck at one value alternates.
        var stuck = BusyRoutine(random: { 0.999 })
        XCTAssertNotEqual(stuck.next().0, stuck.next().0)
    }

    func testRepsFillTheTime() {
        let lift = Moves.weightLifting()
        let reps = BusyRoutine.reps(of: lift, in: 12)
        XCTAssertEqual(lift.duration(reps: reps), 12, accuracy: lift.rep)
        XCTAssertEqual(BusyRoutine.reps(of: lift, in: 0), 1, "at least one")
        XCTAssertNil(BusyRoutine.Move.walk.activity)
        XCTAssertEqual(BusyRoutine.Move.pullUps.activity?.prop, .pullUpBar)
    }
}
