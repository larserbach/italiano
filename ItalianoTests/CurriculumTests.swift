import XCTest
@testable import Italiano

final class CurriculumTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "CurriculumTests")
        defaults.removePersistentDomain(forName: "CurriculumTests")
    }

    private func cell(_ verb: String, _ tense: Tense) -> Cell { Cell(verb: verb, tense: tense) }

    func testVerbOrderCoversEveryVerbOnce() {
        XCTAssertEqual(Curriculum.verbOrder.count, Set(Curriculum.verbOrder).count)
        XCTAssertEqual(Set(Curriculum.verbOrder), Set(VerbLibrary.orderedKeys))
        XCTAssertEqual(Set(Curriculum.tenseOrder), Set(Tense.allCases))
    }

    func testFreshPathStartsWithParlarePresente() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(store.curriculum.unlocked, [cell("parlare", .presente)])
        XCTAssertEqual(store.curriculum.frontier, "parlare")
    }

    func testLevelChangeThresholds() {
        XCTAssertEqual(Curriculum.levelChange(correct: 2, total: 2), 1)
        XCTAssertEqual(Curriculum.levelChange(correct: 4, total: 5), 1)
        XCTAssertEqual(Curriculum.levelChange(correct: 2, total: 3), 0)
        XCTAssertEqual(Curriculum.levelChange(correct: 1, total: 2), 0)
        XCTAssertEqual(Curriculum.levelChange(correct: 1, total: 3), -1)
        XCTAssertEqual(Curriculum.levelChange(correct: 1, total: 1), 0)
        XCTAssertEqual(Curriculum.levelChange(correct: 0, total: 1), 0)
    }

    func testNewVerbAtLevelThreeOfTheFrontier() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.raise("parlare", .presente, lessons: 2)
        XCTAssertEqual(store.unlockedVerbs, ["parlare"])

        let outcome = store.finishFirstRound(results: [cell("parlare", .presente): AnswerCounts(correct: 5, mistakes: 0)])
        XCTAssertEqual(outcome.unlock, Unlock(cell: cell("abitare", .presente), kind: .verb))
        XCTAssertEqual(store.curriculum.frontier, "abitare")

        // parlare stays at 3+, but only the new frontier counts now.
        store.raise("parlare", .presente, lessons: 1)
        XCTAssertEqual(store.unlockedVerbs, ["parlare", "abitare"])
    }

    func testNewTenseAtLevelFiveAndVerbsTakeTurns() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.raise("parlare", .presente, lessons: 3) // → abitare
        store.raise("parlare", .presente, lessons: 2) // parlare 5 → Passato prossimo
        XCTAssertTrue(store.isUnlocked(verb: "parlare", tense: .passatoprossimo))
        XCTAssertEqual(store.curriculum.lastUnlockKind, .tense)

        // abitare reaches 3: a verb is due, and the next parlare tense is not (Passato prossimo is at 0).
        store.raise("abitare", .presente, lessons: 3)
        XCTAssertEqual(store.curriculum.frontier, "essere")
    }

    func testBothDueAlternates() {
        // parlare·Presente at 5 wants the next tense; abitare at 3 wants the next verb.
        seedCurriculum([("parlare", .presente), ("abitare", .presente)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        // parlare·Presente at 5, every other Presente at 3: a verb and a tense are due every time.
        let level = { (cell: Cell) in cell.tense == .presente ? (cell.verb == "parlare" ? 5 : 3) : 0 }
        var state = store.curriculum
        let first = Curriculum.nextUnlock(state, level: level)
        XCTAssertEqual(first, Unlock(cell: cell("essere", .presente), kind: .verb)) // no previous unlock: verb first
        state.apply(first!)
        XCTAssertEqual(Curriculum.nextUnlock(state, level: level),
                       Unlock(cell: cell("parlare", .passatoprossimo), kind: .tense))
    }

    func testTenseSkipsMissingImperative() {
        let state = CurriculumState(sanitizing: [.presente, .passatoprossimo, .imperfetto, .futuro].map { cell("potere", $0) },
                                    lastUnlockKind: .verb)
        let unlock = Curriculum.nextUnlock(state, level: { _ in 5 })
        XCTAssertEqual(unlock, Unlock(cell: cell("potere", .condizionale), kind: .tense))
    }

    func testOpenCapBlocksUnlocks() {
        seedCurriculum([("parlare", .presente), ("abitare", .presente), ("essere", .presente),
                        ("lavorare", .presente)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(store.curriculum.frontier, "lavorare")
        XCTAssertNil(Curriculum.nextUnlock(store.curriculum, level: { _ in 3 }))
        // Once one cell is consolidated there is room again.
        XCTAssertNotNil(Curriculum.nextUnlock(store.curriculum, level: { $0.verb == "parlare" ? 5 : 3 }))
    }

    func testAtMostOneUnlockPerLesson() {
        seedCurriculum([("parlare", .presente), ("abitare", .presente)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.raise("parlare", .presente, lessons: 4)
        store.raise("abitare", .presente, lessons: 2)
        XCTAssertEqual(store.curriculum.unlocked.count, 2)
        let outcome = store.finishFirstRound(results: [
            cell("parlare", .presente): AnswerCounts(correct: 3, mistakes: 0),
            cell("abitare", .presente): AnswerCounts(correct: 3, mistakes: 0),
        ])
        XCTAssertEqual(outcome.levelChanges.count, 2)
        XCTAssertNotNil(outcome.unlock)
        XCTAssertEqual(store.curriculum.unlocked.count, 3)
    }

    func testFirstLessonIsFiveFormsOfParlare() {
        let items = Curriculum.composeLesson(.initial, length: 5, level: { _ in 0 })
        XCTAssertEqual(items.count, 5)
        XCTAssertTrue(items.allSatisfy { $0.verb == "parlare" && $0.tense == .presente })
        XCTAssertEqual(Set(items.map(\.person)).count, 5)
        // Only six forms exist, so a longer lesson stops there.
        XCTAssertEqual(Curriculum.composeLesson(.initial, length: 10, level: { _ in 0 }).count, 6)
    }

    func testLessonSpreadsOverCellsAndKeepsTheNewest() {
        let cells = Curriculum.verbOrder.prefix(8).map { Cell(verb: $0, tense: .presente) }
        let state = CurriculumState(sanitizing: cells)
        for length in [5, 10, 20] {
            for _ in 0..<20 {
                let items = Curriculum.composeLesson(state, length: length, level: { $0.verb == "parlare" ? 1 : 6 })
                XCTAssertEqual(items.count, length)
                let perCell = Dictionary(grouping: items, by: \.cell).mapValues(\.count)
                XCTAssertEqual(perCell.count, (length + 3) / 4)
                XCTAssertTrue(perCell.values.allSatisfy { $0 >= 2 }, "\(perCell)")
                XCTAssertNotNil(perCell[state.newest])
                // At least half the cells are open, and parlare is the only open one besides the newest.
                if length >= 10 { XCTAssertNotNil(perCell[Cell(verb: "parlare", tense: .presente)]) }
                XCTAssertEqual(Set(items.map(\.key)).count, items.count)
            }
        }
    }

    func testMigrationUnlocksPractisedCells() throws {
        let levels = ["parlare": ["presente": 6, "futuro": 2], "capire": ["presente": 1], "fare": ["imperfetto": 0]]
        defaults.set(try JSONEncoder().encode(levels), forKey: "coniugazione-tense-levels")
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(Set(store.curriculum.unlocked),
                       [cell("parlare", .presente), cell("parlare", .futuro), cell("capire", .presente)])
        XCTAssertEqual(store.curriculum.frontier, "capire")
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 6)
        // Saved, so it is not migrated again.
        XCTAssertNotNil(defaults.data(forKey: "coniugazione-curriculum"))
    }

    func testFreePracticeOnlyUsesUnlockedCells() {
        seedCurriculum([("parlare", .presente), ("abitare", .presente), ("parlare", .passatoprossimo)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.conjugation.mode = .free
        store.conjugation.verbs = ["parlare", "abitare"]
        store.conjugation.tenses = [.presente, .passatoprossimo]
        let pool = ConjugationLesson.freePool(store)
        XCTAssertEqual(pool.count, 18)
        XCTAssertFalse(pool.contains { $0.verb == "abitare" && $0.tense == .passatoprossimo })
        XCTAssertEqual(store.unlockedTenses, [.presente, .passatoprossimo])
    }
}
