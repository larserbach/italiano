import XCTest
@testable import Italiano

final class MemoryStateTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func after(days: Double) -> Date { start + days * 86_400 }

    func testFirstRating() {
        let again = MemoryState.updated(nil, .again, at: start)
        let correct = MemoryState.updated(nil, .correct, at: start)
        let good = MemoryState.updated(nil, .good, at: start)
        XCTAssertLessThan(again.stability, correct.stability)
        XCTAssertLessThan(correct.stability, good.stability)
        XCTAssertLessThan(again.retrievability, good.retrievability)
        XCTAssertGreaterThan(again.difficulty, good.difficulty)
        XCTAssertEqual(good.good, 1)
        XCTAssertEqual(again.good, 0)
    }

    func testRetrievabilityHalvesAfterOneStability() {
        let state = MemoryState(difficulty: 5, stability: 2, retrievability: 0.9, last: start, lastRating: .good, answers: 1, good: 1)
        XCTAssertEqual(state.retrievability(at: start), 0.9, accuracy: 1e-9)
        XCTAssertEqual(state.retrievability(at: after(days: 2)), 0.45, accuracy: 1e-9)
    }

    func testAgainLowersStabilityStronglyAndRetrievabilityModerately() {
        let state = MemoryState(difficulty: 5, stability: 4, retrievability: 1, last: start, lastRating: .good, answers: 3, good: 3)
        let next = MemoryState.updated(state, .again, at: after(days: 4)) // retrievability 0.5 by now
        XCTAssertEqual(next.stability, 1.6, accuracy: 1e-9)
        XCTAssertEqual(next.retrievability, 0.35, accuracy: 1e-9)
        XCTAssertEqual(next.difficulty, 6.5)
        XCTAssertEqual(next.lastRating, .again)
        XCTAssertEqual(next.answers, 4)
    }

    func testCorrectChangesNeitherStabilityNorRetrievability() {
        let state = MemoryState(difficulty: 5, stability: 4, retrievability: 1, last: start, lastRating: .good, answers: 3, good: 3)
        let next = MemoryState.updated(state, .correct, at: after(days: 4))
        XCTAssertEqual(next.stability, 4)
        XCTAssertEqual(next.retrievability, 1)
        XCTAssertEqual(next.last, start)
        XCTAssertEqual(next.retrievability(at: after(days: 4)), state.retrievability(at: after(days: 4)))
        XCTAssertEqual(next.lastRating, .correct)
        XCTAssertEqual(next.answers, 4)
        XCTAssertEqual(next.good, 3)
    }

    func testGoodRaisesBothMoreAfterAGap() {
        let state = MemoryState(difficulty: 5, stability: 2, retrievability: 1, last: start, lastRating: .good, answers: 1, good: 1)
        let repeated = MemoryState.updated(state, .good, at: start)
        let spaced = MemoryState.updated(state, .good, at: after(days: 2)) // retrievability 0.5
        XCTAssertGreaterThan(repeated.stability, 2)
        XCTAssertGreaterThan(spaced.stability, repeated.stability)
        XCTAssertEqual(spaced.retrievability, 0.9, accuracy: 1e-9)
        XCTAssertEqual(spaced.difficulty, 4.5)
        XCTAssertEqual(spaced.good, 2)
    }
}

final class LearningMemoryTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testAnswerUpdatesFormVerbAndGroupPattern() {
        var memory = LearningMemory()
        let form = FormKey(verb: "parlare", tense: .presente, person: 1)
        memory.record(form, .good, at: now)
        XCTAssertNotNil(memory.forms[form])
        XCTAssertNotNil(memory.cells[form.cell])
        XCTAssertNotNil(memory.patterns[PatternKey(form)!])
        // A new -are verb is partly known through the pattern; an irregular verb is not.
        XCTAssertGreaterThan(memory.known(FormKey(verb: "abitare", tense: .presente, person: 1), at: now), 0)
        XCTAssertEqual(memory.known(FormKey(verb: "essere", tense: .presente, person: 1), at: now), 0)
    }

    func testIrregularVerbsHaveNoPattern() {
        var memory = LearningMemory()
        memory.record(FormKey(verb: "essere", tense: .presente, person: 0), .good, at: now)
        XCTAssertTrue(memory.patterns.isEmpty)
        XCTAssertEqual(memory.cells.count, 1)
    }

    func testPassatoProssimoPatternsDependOnTheAuxiliary() {
        let withAvere = PatternKey(FormKey(verb: "parlare", tense: .passatoprossimo, person: 0))
        let withEssere = PatternKey(FormKey(verb: "arrivare", tense: .passatoprossimo, person: 0))
        XCTAssertNotEqual(withAvere, withEssere)
        XCTAssertEqual(PatternKey(FormKey(verb: "parlare", tense: .presente, person: 0)),
                       PatternKey(FormKey(verb: "arrivare", tense: .presente, person: 0)))
    }

    func testMemoryRoundTripsThroughJSON() throws {
        var memory = LearningMemory()
        memory.record(FormKey(verb: "parlare", tense: .passatoprossimo, person: 2), .again, at: now)
        let decoded = try JSONDecoder().decode(LearningMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(decoded, memory)
    }
}

final class LearningPoolTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "LearningPoolTests")
        defaults.removePersistentDomain(forName: "LearningPoolTests")
    }

    private func cell(_ verb: String, _ tense: Tense = .presente) -> Cell { Cell(verb: verb, tense: tense) }

    /// Memory in which every form of `cells` was just answered Good.
    private func settled(_ cells: [Cell]) -> LearningMemory {
        var memory = LearningMemory()
        for form in cells.flatMap(Curriculum.forms) { memory.record(form, .good, at: now) }
        return memory
    }

    func testVerbOrderCoversEveryVerbOnce() {
        XCTAssertEqual(Curriculum.verbOrder.count, Set(Curriculum.verbOrder).count)
        XCTAssertEqual(Set(Curriculum.verbOrder), Set(VerbLibrary.orderedKeys))
        XCTAssertEqual(Set(Curriculum.tenseOrder), Set(Tense.allCases))
    }

    func testFreshPoolStartsWithFourVerbs() {
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.cells, ["parlare", "avere", "essere", "dormire"].map { cell($0) })
        XCTAssertEqual(store.unlockedTenses, [.presente])
    }

    func testMissingFamiliesComeFirstThenIrregularAndRegularTakeTurns() {
        var pool = LearningPool.initial(at: now)
        var order: [String] = []
        for _ in 0..<5 {
            let next = pool.nextCell()!
            order.append(next.verb)
            pool = LearningPool(cells: pool.cells + [next], at: now)
        }
        // -ere and -ire (isc) are missing at the start; then an irregular verb, then a regular one.
        XCTAssertEqual(order, ["credere", "capire", "fare", "abitare", "andare"])
    }

    func testNextTenseOpensWithTenPresenteVerbs() {
        let nine = ["parlare", "avere", "essere", "dormire", "credere", "capire", "fare", "abitare", "andare"].map { cell($0) }
        XCTAssertEqual(LearningPool(cells: nine, at: now).nextCell()?.tense, .presente)
        let ten = LearningPool(cells: nine + [cell("lavorare")], at: now)
        XCTAssertEqual(ten.nextCell(), cell("parlare", .passatoprossimo))
    }

    func testFamiliesAreCoveredInANewTenseBeforeMoreVerbs() {
        let presente = ["parlare", "avere", "essere", "dormire", "credere", "capire", "fare", "abitare", "andare", "lavorare"]
        let pool = LearningPool(cells: presente.map { cell($0) } + [cell("parlare", .passatoprossimo)], at: now)
        // Only -are is in the Passato prossimo yet, so the next family comes first: -ere with credere.
        XCTAssertEqual(pool.nextCell(), cell("credere", .passatoprossimo))
    }

    func testTwoGoodLessonsAndASettledPoolAddACell() {
        var pool = LearningPool.initial(at: now)
        let memory = settled(pool.cells)
        let good = Array(repeating: Rating.good, count: 10)
        XCTAssertEqual(pool.finishLesson(ratings: good, memory: memory, at: now), .init(cell: cell("credere"), reason: .ready))
        XCTAssertEqual(pool.cells.last, cell("credere"))
    }

    func testTheLastTwoLessonsNeedNinetyPercent() {
        let memory = settled(LearningPool.startCells)
        let eightOfTen = Array(repeating: Rating.good, count: 8) + [.again, .again]
        // 8 + 10 of 20 is enough …
        var pool = LearningPool.initial(at: now)
        XCTAssertNil(pool.finishLesson(ratings: eightOfTen, memory: memory, at: now))
        XCTAssertNotNil(pool.finishLesson(ratings: Array(repeating: .good, count: 10), memory: memory, at: now))
        // … 8 + 9 of 20 is not.
        var other = LearningPool.initial(at: now)
        XCTAssertNil(other.finishLesson(ratings: eightOfTen, memory: memory, at: now))
        XCTAssertNil(other.finishLesson(ratings: Array(repeating: .good, count: 9) + [.again], memory: memory, at: now))
    }

    func testLookedUpAnswersCountHalf() {
        let memory = settled(LearningPool.startCells)
        var pool = LearningPool.initial(at: now)
        // 8 Good + 2 looked up = 9 of 10 points.
        XCTAssertNotNil(pool.finishLesson(ratings: Array(repeating: .good, count: 8) + [.correct, .correct], memory: memory, at: now))
        var other = LearningPool.initial(at: now)
        // 7 Good + 3 looked up = 8.5 of 10.
        XCTAssertNil(other.finishLesson(ratings: Array(repeating: .good, count: 7) + [.correct, .correct, .correct], memory: memory, at: now))
    }

    func testAWeakPoolBlocksEvenAfterGoodLessons() {
        var pool = LearningPool.initial(at: now)
        var memory = settled(pool.cells)
        memory.record(FormKey(verb: "essere", tense: .presente, person: 0), .again, at: now)
        memory.record(FormKey(verb: "dormire", tense: .presente, person: 0), .again, at: now)
        // credere is a new family (eager): 80 % of the pool must be settled; 2 of 4 is not enough.
        XCTAssertNil(pool.finishLesson(ratings: Array(repeating: .good, count: 10), memory: memory, at: now))
    }

    func testFastTrackForAProvenFamily() {
        let cells = ["parlare", "avere", "essere", "dormire", "credere", "capire", "fare"].map { cell($0) }
        var pool = LearningPool(cells: cells, at: now)
        XCTAssertEqual(pool.nextCell(), cell("abitare")) // a regular -are verb is next
        for person in 0..<6 { pool.record(FormKey(verb: "parlare", tense: .presente, person: person), .good) }
        // A bad lesson elsewhere does not matter: -are · Presente is proven.
        let addition = pool.finishLesson(ratings: Array(repeating: .again, count: 10), memory: LearningMemory(), at: now)
        XCTAssertEqual(addition, .init(cell: cell("abitare"), reason: .fastTrack))
    }

    func testAnAgainEndsTheFastTrackStreak() {
        var pool = LearningPool.initial(at: now)
        for person in 0..<5 { pool.record(FormKey(verb: "parlare", tense: .presente, person: person), .good) }
        pool.record(FormKey(verb: "parlare", tense: .presente, person: 5), .again)
        pool.record(FormKey(verb: "parlare", tense: .presente, person: 0), .good)
        XCTAssertEqual(pool.streaks[.init(family: .are, tense: .presente)]?.count, 1)
        // Looked-up answers neither count nor break it; irregular verbs have no streak.
        pool.record(FormKey(verb: "parlare", tense: .presente, person: 1), .correct)
        pool.record(FormKey(verb: "essere", tense: .presente, person: 1), .good)
        XCTAssertEqual(pool.streaks.count, 1)
        XCTAssertEqual(pool.streaks[.init(family: .are, tense: .presente)]?.count, 1)
    }

    func testLessonPickingFillsTheLessonAndMixes() {
        var rng = SeededGenerator(state: 7)
        let one = LearningPool(cells: [cell("parlare")], at: now - 2 * 86_400)
        let single = Curriculum.pickLesson(from: Curriculum.forms(cell("parlare")), pool: one, memory: LearningMemory(),
                                           length: 10, at: now, using: &rng)
        XCTAssertEqual(single.count, 6) // only six forms exist

        let pool = LearningPool.initial(at: now - 2 * 86_400)
        for _ in 0..<20 {
            let picked = Curriculum.pickLesson(from: pool.cells.flatMap(Curriculum.forms), pool: pool, memory: LearningMemory(),
                                               length: 10, at: now, using: &rng)
            XCTAssertEqual(picked.count, 10)
            XCTAssertEqual(Set(picked).count, 10)
            XCTAssertTrue(Dictionary(grouping: picked, by: \.cell).values.allSatisfy { $0.count <= 4 })
        }
    }

    func testAWeakPersonIsTrainedMore() {
        var rng = SeededGenerator(state: 3)
        let pool = LearningPool.initial(at: now - 2 * 86_400)
        var memory = LearningMemory()
        for form in pool.cells.flatMap(Curriculum.forms) {
            memory.record(form, form.person == 3 ? .again : .good, at: now) // noi is weak
        }
        var noi = 0, total = 0
        for _ in 0..<50 {
            let picked = Curriculum.pickLesson(from: pool.cells.flatMap(Curriculum.forms), pool: pool, memory: memory,
                                               length: 10, at: now, using: &rng)
            noi += picked.filter { $0.person == 3 }.count
            total += picked.count
        }
        XCTAssertGreaterThan(Double(noi) / Double(total), 0.3) // a sixth would be even
    }

    func testPoolRoundTripsThroughJSON() throws {
        var pool = LearningPool.initial(at: now)
        pool.record(FormKey(verb: "parlare", tense: .presente, person: 0), .good)
        _ = pool.finishLesson(ratings: [.good], memory: settled(pool.cells), at: now)
        XCTAssertEqual(try JSONDecoder().decode(LearningPool.self, from: JSONEncoder().encode(pool)), pool)
    }
}

final class MigrationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "MigrationTests")
        defaults.removePersistentDomain(forName: "MigrationTests")
    }

    func testPerLessonLevelsAndTheOldPathCarryOver() throws {
        defaults.set(try JSONEncoder().encode(["capire": ["presente": 3, "futuro": 0]]), forKey: "coniugazione-tense-levels")
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "unlocked": [["verb": "parlare", "tense": "presente"], ["verb": "capire", "tense": "presente"],
                         ["verb": "capire", "tense": "passatoprossimo"]],
            "frontier": "capire",
        ]), forKey: "coniugazione-curriculum")
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.cells, LearningPool.startCells + [Cell(verb: "capire", tense: .presente),
                                                                  Cell(verb: "capire", tense: .passatoprossimo)])
        XCTAssertEqual(store.stability(of: Cell(verb: "capire", tense: .presente)), 0.5 * pow(2, 0.96), accuracy: 1e-9)
        XCTAssertNil(store.state(of: Cell(verb: "capire", tense: .futuro)))
        XCTAssertNil(defaults.data(forKey: "coniugazione-tense-levels"))
        XCTAssertNil(defaults.data(forKey: "coniugazione-curriculum"))
        XCTAssertEqual(makeStore(defaults).pool.cells, store.pool.cells)
    }

    func testHalfLivesBecomeStabilities() throws {
        let last = Date(timeIntervalSinceReferenceDate: 799_000_000)
        let old = ["parlare": ["presente": ["halfLife": 2.5, "last": last.timeIntervalSinceReferenceDate, "answers": 4, "correct": 3]]]
        defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: "coniugazione-memory")
        let store = makeStore(defaults)
        let state = try XCTUnwrap(store.state(of: Cell(verb: "parlare", tense: .presente)))
        XCTAssertEqual(state.stability, 2.5)
        XCTAssertEqual(state.last, last)
        XCTAssertNil(defaults.data(forKey: "coniugazione-memory"))
    }
}

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
        store.record(ConjugationItem(verb: "parlare", tense: .presente, person: 1), .correct)

        let entries = AnswerLog(fileURL: url).entries
        XCTAssertEqual(entries.map(\.rating), [.again, .correct])
        XCTAssertNil(entries[0].stabilityBefore)
        XCTAssertEqual(entries[1].stabilityBefore, entries[0].stabilityAfter)
        XCTAssertEqual(entries[1].stabilityAfter, entries[0].stabilityAfter) // Correct changes nothing
        XCTAssertEqual(store.log.entries(for: "parlare").count, 2)
        XCTAssertTrue(store.log.entries(for: "abitare").isEmpty)

        // Over the cap, the oldest lines are dropped on load.
        let line = String(data: try JSONEncoder().encode(entries[1]), encoding: .utf8)! + "\n"
        try String(repeating: line, count: AnswerLog.maxEntries + 5).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(AnswerLog(fileURL: url).entries.count, AnswerLog.maxEntries)

        store.resetProgress()
        XCTAssertTrue(store.log.entries.isEmpty)
        XCTAssertTrue(AnswerLog(fileURL: url).entries.isEmpty)
    }
}
