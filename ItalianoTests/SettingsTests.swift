import XCTest
@testable import Italiano

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SettingsTests")
        defaults.removePersistentDomain(forName: "SettingsTests")
    }

    func testSettingsPersist() {
        seedPool([("parlare", .presente), ("parlare", .imperfetto), ("parlare", .congiuntivo)], in: defaults)
        let store = makeStore(defaults)
        store.conjugation.tenses = [.imperfetto, .congiuntivo]
        store.aux.length = .all
        let reloaded = makeStore(defaults)
        XCTAssertEqual(reloaded.conjugation.tenses, [.imperfetto, .congiuntivo])
        XCTAssertEqual(reloaded.aux.length, .all)
    }

    func testResetProgressClearsLevelsMistakesAndHistoryButKeepsSettings() {
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("reset-\(UUID().uuidString).json")
        let logURL = historyURL.appendingPathExtension("jsonl")
        defer {
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.removeItem(at: logURL)
        }

        seedPool([("parlare", .presente), ("capire", .presente), ("capire", .futuro)], in: defaults)
        let store = makeStore(defaults, historyURL: historyURL, logURL: logURL)
        store.conjugation.mode = .free
        store.conjugation.tenses = [.futuro]
        store.conjugation.length = .count(10)
        store.practise("parlare", .presente)
        store.record(ConjugationItem(verb: "capire", tense: .futuro, person: 0), .again)
        store.recordAuxAnswer(verb: "arrivare", correct: true)
        XCTAssertNotNil(store.state(of: MemoryKey(verb: "parlare", tense: .presente, person: 0)))
        XCTAssertFalse(store.log.entries.isEmpty)
        XCTAssertTrue(store.isRecentMistake(verb: "capire", tenses: [.futuro]))
        XCTAssertFalse(store.history.isEmpty)

        store.resetProgress()

        for reloaded in [store, makeStore(defaults, historyURL: historyURL, logURL: logURL)] {
            XCTAssertNil(reloaded.state(of: MemoryKey(verb: "parlare", tense: .presente, person: 0)))
            XCTAssertTrue(reloaded.log.entries.isEmpty)
            XCTAssertEqual(reloaded.auxLevel(of: "arrivare"), 0)
            XCTAssertFalse(reloaded.isRecentMistake(verb: "capire", tenses: [.futuro]))
            XCTAssertTrue(reloaded.history.isEmpty)
            XCTAssertEqual(reloaded.pool.units, LearningPool.startUnits)
            // Free practice falls back to what is in the pool again; the rest stays.
            XCTAssertEqual(reloaded.conjugation.verbs, ["parlare"])
            XCTAssertEqual(reloaded.conjugation.tenses, [.presente])
            XCTAssertEqual(reloaded.conjugation.mode, .free)
            XCTAssertEqual(reloaded.conjugation.length, .count(10))
        }
    }

    func testFreshInstallStartsWithTheFirstVerbPresenteAndFiveQuestions() {
        let store = makeStore(defaults)
        XCTAssertEqual(store.conjugation.verbs, ["parlare"])
        XCTAssertEqual(store.conjugation.tenses, [.presente])
        XCTAssertEqual(store.conjugation.length, .count(5))
        XCTAssertEqual(store.conjugation.mode, .path)
        XCTAssertEqual(store.pool.units, LearningPool.startUnits)
    }

    func testSavedSelectionWithoutKnownVerbsFallsBackToTheFirstVerb() throws {
        var settings = ProgressStore.ConjugationSettings()
        settings.verbs = ["xyz"]
        defaults.set(try JSONEncoder().encode(settings), forKey: "coniugazione-settings")
        XCTAssertEqual(makeStore(defaults).conjugation.verbs, ["parlare"])
    }

    func testSettingsSavedWithTheOldDirectionStillLoad() throws {
        seedPool([("parlare", .presente), ("parlare", .futuro)], in: defaults)
        var settings = ProgressStore.ConjugationSettings()
        settings.verbs = ["parlare"]
        settings.tenses = [.futuro]
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        saved["direction"] = "mixed"
        saved["mode"] = nil // saved before the learning path existed
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "coniugazione-settings")

        let store = makeStore(defaults)
        XCTAssertEqual(store.conjugation.verbs, ["parlare"])
        XCTAssertEqual(store.conjugation.tenses, [.futuro])
        XCTAssertEqual(store.conjugation.mode, .path)
    }
}
