import Foundation
import Testing
@testable import ASBCore

private func sample() -> Snapshot {
    Snapshot(
        generatedAt: 1_792_891_080_000,
        invalidFiles: 0,
        activeMutes: 1,
        header: .init(state: .waiting, symbol: "exclamationmark.circle.fill", color: "#D70015,#FF453A", count: 1),
        sessions: [
            .init(
                sessionId: "s1", project: "api-gateway", title: "Add rate limiting",
                cwd: "/Users/alex/code/api-gateway", shown: .waiting, reason: "permission",
                since: 1_792_891_073_038, label: "api-gateway — Add rate limiting", word: "permission",
                detail: "6s", herdrPane: "w2:p1", focusable: true,
                symbol: "exclamationmark.circle.fill", color: "#D70015,#FF453A",
                subagents: [.init(id: "a1", type: "Explore", since: 1_792_891_070_000, detail: "10s")]
            ),
        ]
    )
}

@Test func snapshotRoundTrips() throws {
    let data = try sample().encodedJSON()
    let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
    #expect(decoded == sample())
}

@Test func snapshotKeysAreSortedAndOptionalsOmitted() throws {
    let json = String(decoding: try sample().encodedJSON(), as: UTF8.self)
    #expect(json.hasPrefix(#"{"activeMutes":1,"generatedAt":"#))
    #expect(!json.contains("muteUntil"))
    #expect(!json.contains("transcriptPath"))
    // Encoding twice gives the same bytes.
    #expect(try sample().encodedJSON() == sample().encodedJSON())
}

@Test func headerWithoutCountOmitsIt() throws {
    let header = Snapshot.Header(state: .none, symbol: "sparkle", color: "#C7C7CC,#48484A")
    let json = String(decoding: try JSONEncoder().encode(header), as: UTF8.self)
    #expect(!json.contains("count"))
}
