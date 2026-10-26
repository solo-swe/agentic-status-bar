import Foundation
import Testing
@testable import ASBCore

private func tempDir() throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("asb-writer-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

@Test func theLockIsTakenAndReleased() throws {
    let file = try tempDir() + "/s1.json"
    var lockedWhileRunning = false
    let acquired = StateWriter.withLock(file) {
        lockedWhileRunning = FileManager.default.fileExists(atPath: file + ".lock")
    }
    #expect(acquired && lockedWhileRunning)
    #expect(!FileManager.default.fileExists(atPath: file + ".lock"))
}

@Test func aHeldLockMakesTheWriterGiveUpQuietly() throws {
    let file = try tempDir() + "/s1.json"
    try FileManager.default.createDirectory(atPath: file + ".lock", withIntermediateDirectories: false)
    var ran = false
    let start = Date()
    #expect(!StateWriter.withLock(file, tries: 5, interval: 0.01) { ran = true })
    #expect(!ran)
    #expect(Date().timeIntervalSince(start) < 1)
    // Someone else's lock is left alone.
    #expect(FileManager.default.fileExists(atPath: file + ".lock"))
}

@Test func atomicWriteLeavesNoTempFile() throws {
    let dir = try tempDir()
    let file = dir + "/s1.json"
    #expect(StateWriter.atomicWrite(Data("one\n".utf8), to: file))
    #expect(StateWriter.atomicWrite(Data("two\n".utf8), to: file))
    #expect(try String(contentsOfFile: file, encoding: .utf8) == "two\n")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["s1.json"])
}
