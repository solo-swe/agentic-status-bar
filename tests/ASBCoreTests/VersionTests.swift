import Testing
@testable import ASBCore

@Test func versionIsSemantic() {
    let parts = ASBVersion.current.split(separator: ".")
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { Int($0) != nil })
}
