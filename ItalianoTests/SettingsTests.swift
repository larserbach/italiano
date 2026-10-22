import XCTest
@testable import Italiano

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SettingsTests")
        defaults.removePersistentDomain(forName: "SettingsTests")
    }

    func testSettingsPersist() {
        let store = makeStore(defaults)
        store.conjugation.length = .count(20)
        store.aux.length = .all
        let reloaded = makeStore(defaults)
        XCTAssertEqual(reloaded.conjugation.length, .count(20))
        XCTAssertEqual(reloaded.aux.length, .all)
    }

    func testResetProgressClearsLevelsAndHistoryButKeepsSettings() {
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("reset-\(UUID().uuidString).json")
        let logURL = historyURL.appendingPathExtension("jsonl")
        defer {
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.removeItem(at: logURL)
        }

        seedPool([("parlare", .presente), ("capire", .presente), ("capire", .futuro)], in: defaults)
        let store = makeStore(defaults, historyURL: historyURL, logURL: logURL)
        store.conjugation.length = .count(10)
        store.practise("parlare", .presente)
        store.record(ConjugationItem(verb: "capire", tense: .futuro, person: 0), .again)
        store.recordAuxAnswer(verb: "arrivare", correct: true)
        XCTAssertNotNil(store.state(of: MemoryKey(verb: "parlare", tense: .presente, person: 0)))
        XCTAssertFalse(store.log.entries.isEmpty)
        XCTAssertFalse(store.history.isEmpty)

        store.resetProgress()

        for reloaded in [store, makeStore(defaults, historyURL: historyURL, logURL: logURL)] {
            XCTAssertNil(reloaded.state(of: MemoryKey(verb: "parlare", tense: .presente, person: 0)))
            XCTAssertTrue(reloaded.log.entries.isEmpty)
            XCTAssertEqual(reloaded.auxLevel(of: "arrivare"), 0)
            XCTAssertTrue(reloaded.history.isEmpty)
            XCTAssertEqual(reloaded.pool.units, LearningPool.startUnits)
            XCTAssertEqual(reloaded.conjugation.length, .count(10))
        }
    }

    func testFreshInstallStartsWithTheLearningPathAndFiveQuestions() {
        let store = makeStore(defaults)
        XCTAssertEqual(store.conjugation.length, .count(5))
        XCTAssertEqual(store.pool.units, LearningPool.startUnits)
    }

    func testSettingsSavedWithFreePracticeStillLoad() throws {
        var settings = ProgressStore.ConjugationSettings()
        settings.length = .count(10)
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        saved["mode"] = "free"
        saved["verbs"] = ["parlare"]
        saved["tenses"] = ["futuro"]
        saved["direction"] = "mixed"
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "coniugazione-settings")

        XCTAssertEqual(makeStore(defaults).conjugation.length, .count(10))
    }
}
