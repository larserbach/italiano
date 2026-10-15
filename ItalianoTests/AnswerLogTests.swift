import XCTest
@testable import Italiano

final class AnswerLogTests: XCTestCase {
    func testEntriesPersistAndAreTrimmed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let defaults = UserDefaults(suiteName: "AnswerLogTests")!
        defaults.removePersistentDomain(forName: "AnswerLogTests")
        let clock = TestClock()
        let store = makeStore(defaults, clock: clock, logURL: url)
        store.record(ConjugationItem(verb: "parlare", tense: .presente, person: 1), .again)
        clock.advance(days: 1)
        // Another -are verb, same pattern: it continues where parlare left off.
        store.record(ConjugationItem(verb: "abitare", tense: .presente, person: 1), .correct)

        let entries = AnswerLog(fileURL: url).entries
        XCTAssertEqual(entries.map(\.rating), [.again, .correct])
        XCTAssertEqual(entries.map(\.verb), ["parlare", "abitare"])
        XCTAssertNil(entries[0].stabilityBefore)
        XCTAssertEqual(entries[1].stabilityBefore, entries[0].stabilityAfter)
        XCTAssertEqual(entries[1].stabilityAfter, entries[0].stabilityAfter) // Correct changes nothing
        XCTAssertEqual(store.log.entries, entries)

        // Over the cap, the oldest lines are dropped on load.
        let line = String(data: try JSONEncoder().encode(entries[1]), encoding: .utf8)! + "\n"
        try String(repeating: line, count: AnswerLog.maxEntries + 5).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(AnswerLog(fileURL: url).entries.count, AnswerLog.maxEntries)

        store.resetProgress()
        XCTAssertTrue(store.log.entries.isEmpty)
        XCTAssertTrue(AnswerLog(fileURL: url).entries.isEmpty)
    }
}
