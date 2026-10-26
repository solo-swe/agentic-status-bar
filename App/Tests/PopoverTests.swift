import ASBCore
import XCTest
@testable import Agentic_Status_Bar

final class PopoverTests: XCTestCase {
    private func session(
        _ id: String, project: String, title: String = "", cwd: String? = nil, transcript: String? = nil,
        muted: Bool = false, focusable: Bool = false, subagents: [Snapshot.Subagent] = []
    ) -> Snapshot.Session {
        Snapshot.Session(
            sessionId: id, project: project, title: title, cwd: cwd, shown: .busy, since: 0, label: "",
            word: "working", detail: "2m", muted: muted, transcriptPath: transcript, focusable: focusable,
            symbol: "bolt.fill", color: "#000000", subagents: subagents)
    }

    func testAFullRowMenu() {
        let menu = RowAction.menu(for: session(
            "a", project: "web", cwd: "/w/web", transcript: "/t/a.jsonl", focusable: true))
        XCTAssertEqual(menu.map(\.action), [
            "focus", "mute-hour", "mute-today", "copy-id", "copy-cwd", "open-folder", "reveal-transcript",
        ])
        XCTAssertEqual(menu.filter(\.startsGroup).map(\.action), ["mute-hour", "copy-id", "open-folder"])
        XCTAssertTrue(menu.allSatisfy { $0.sessionId == "a" })
    }

    func testAMutedRowOffersUnmuteAndSkipsWhatItLacks() {
        let menu = RowAction.menu(for: session("b", project: "api", muted: true))
        XCTAssertEqual(menu.map(\.action), ["unmute", "copy-id"])
        XCTAssertEqual(menu.filter(\.startsGroup).map(\.action), ["copy-id"])
    }

    func testOnlyAppSwitchingActionsClose() {
        XCTAssertEqual(PopoverView.closingActions, ["focus", "open-folder", "reveal-transcript"])
    }

    func testRowsFollowTheSnapshotWithSubagentsIndented() {
        let snapshot = Snapshot(
            generatedAt: 0, header: .init(state: .busy, symbol: "bolt.fill", color: "#000000", count: 2),
            sessions: [
                session("a", project: "web", title: "fix login", focusable: true,
                        subagents: [.init(id: "s1", type: "Explore", since: 0, detail: "12s")]),
                session("b", project: "api", muted: true),
            ])
        let rows = RowItem.rows(snapshot)
        XCTAssertEqual(rows.map(\.id), ["a", "a/s1", "b"])
        XCTAssertEqual(rows[0].text, "web — fix login")
        XCTAssertEqual(rows[0].focusId, "a")
        XCTAssertTrue(rows[1].indented)
        XCTAssertEqual(rows[1].text, "Explore")
        XCTAssertEqual(rows[1].detail, "12s")
        XCTAssertEqual(rows[1].focusId, "a")
        XCTAssertEqual(rows[2].text, "api")
        XCTAssertTrue(rows[2].muted)
        XCTAssertNil(rows[2].focusId)
        XCTAssertTrue(rows[1].actions.isEmpty)
        XCTAssertFalse(rows[0].actions.isEmpty)
    }

    func testTheInvalidFilesNote() {
        XCTAssertEqual(PopoverView.invalidNote(1), "1 state file can't be read")
        XCTAssertEqual(PopoverView.invalidNote(3), "3 state files can't be read")
    }
}
