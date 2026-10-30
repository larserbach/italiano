import XCTest
@testable import Italiano

final class LearningPoolTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "LearningPoolTests")
        defaults.removePersistentDomain(forName: "LearningPoolTests")
    }

    /// Feeds `ratings` to a unit, going round its persons.
    private func answer(_ pool: inout LearningPool, _ unit: PoolUnit, _ ratings: [Rating]) {
        for (index, rating) in ratings.enumerated() {
            let person = unit.persons[index % unit.persons.count]
            let key: MemoryKey = switch unit {
            case .group(let family, let tense): .pattern(PatternKey(family: family, tense: tense, person: person))
            case .irregular(let verb, let tense): .form(FormKey(verb: verb, tense: tense, person: person))
            }
            pool.record(key, rating)
        }
    }

    private func good(_ count: Int) -> [Rating] { Array(repeating: .good, count: count) }

    func testVerbOrderCoversEveryVerbOnce() {
        XCTAssertEqual(Curriculum.verbOrder.count, Set(Curriculum.verbOrder).count)
        XCTAssertEqual(Set(Curriculum.verbOrder), Set(VerbLibrary.orderedKeys))
        XCTAssertEqual(Set(Curriculum.tenseOrder), Set(Tense.allCases))
    }

    func testStartsWithAllAreVerbsAndEssere() {
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.units, [.group(.are, .presente), .irregular("essere", .presente)])
        let verbs = store.pool.units.flatMap(store.pool.verbs(of:))
        XCTAssertEqual(Set(verbs), Set(PoolUnit.group(.are, .presente).verbs + ["essere"]))
        // andare counts for -are where it is regular (andavo), essere nowhere.
        XCTAssertFalse(verbs.contains("andare"))
        XCTAssertTrue(VerbFamily.are.verbs.contains("andare"))
        XCTAssertFalse(VerbFamily.ere.verbs.contains("essere"))
        XCTAssertEqual(verbs.count, 21)
    }

    func testDropsUnitsOfVerbsInTensesTheyAreRegularIn() throws {
        // Saved when scrivere counted as irregular in every tense.
        let old = LearningPool(units: [.group(.are, .presente), .irregular("essere", .presente), .irregular("avere", .presente)], at: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try XCTUnwrap(String(data: encoder.encode(old), encoding: .utf8)).replacingOccurrences(of: "avere", with: "scrivere")
        defaults.set(Data(json.utf8), forKey: "coniugazione-group-pool")

        XCTAssertEqual(makeStore(defaults).pool.units, [.group(.are, .presente), .irregular("essere", .presente)])
        let saved = try JSONDecoder().decode(LearningPool.self, from: XCTUnwrap(defaults.data(forKey: "coniugazione-group-pool")))
        XCTAssertEqual(saved.units, [.group(.are, .presente), .irregular("essere", .presente)])
    }

    func testEachPersonKeepsItsLastFourAnswers() {
        var pool = LearningPool.initial(at: now)
        let are = PoolUnit.group(.are, .presente)
        let io = MemoryKey.pattern(PatternKey(family: .are, tense: .presente, person: are.persons[0]))
        for rating in Array(repeating: Rating.again, count: 3) + good(4) { pool.record(io, rating) }
        // However often the others are asked, io keeps its last 4 answers.
        for index in 0..<40 {
            pool.record(.pattern(PatternKey(family: .are, tense: .presente, person: are.persons[1 + index % 5])), .good)
        }
        let progress = pool.progress(of: are)
        XCTAssertEqual(progress.answers, 24)
        XCTAssertEqual(progress.counted, 12)
        XCTAssertEqual(progress.needed, 12)
        XCTAssertEqual(progress.share, 1)
        XCTAssertTrue(progress.missingPersons.isEmpty)
        XCTAssertTrue(progress.performsWell)
    }

    func testAPersonWithTooFewAnswersHoldsBack() {
        var pool = LearningPool.initial(at: now)
        let are = PoolUnit.group(.are, .presente)
        for index in 0..<40 {
            pool.record(.pattern(PatternKey(family: .are, tense: .presente, person: are.persons[1 + index % 5])), .good)
        }
        pool.record(.pattern(PatternKey(family: .are, tense: .presente, person: are.persons[0])), .good)
        XCTAssertEqual(pool.progress(of: are).missingPersons, [are.persons[0]])
        XCTAssertFalse(pool.progress(of: are).performsWell)
    }

    func testAWindowSavedAsTheLastTwentyAnswersKeepsFourPerPerson() throws {
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LearningPool.Window())) as? [String: Any])
        saved["ratings"] = Array(repeating: "again", count: 2) + Array(repeating: "good", count: 24)
        saved["persons"] = (0..<26).map { $0 % 6 }
        var old = try JSONDecoder().decode(LearningPool.Window.self, from: JSONSerialization.data(withJSONObject: saved))
        // Persons 0 and 1 had 5 answers, the oldest one Again: it goes.
        XCTAssertEqual(old.ratings.count, 24)
        XCTAssertEqual(old.share, 1)
        XCTAssertEqual((0..<6).map(old.count(of:)), [4, 4, 4, 4, 4, 4])
        old.append(.again, person: 0)
        XCTAssertEqual(old.count(of: 0), 4)
    }

    func testAGroupThatPerformsWellBringsTheNextGroupAndItsNextTense() {
        var pool = LearningPool.initial(at: now)
        let are = PoolUnit.group(.are, .presente)
        answer(&pool, are, good(16) + Array(repeating: .again, count: 4)) // exactly 80 %
        let additions = pool.finishLesson(at: now)
        XCTAssertEqual(additions.map(\.unit), [.group(.ere, .presente), .group(.are, .passatoprossimo)])
        XCTAssertTrue(additions.allSatisfy { $0.cause == are })
        XCTAssertTrue(pool.progress(of: are).passed)
        // Only once.
        answer(&pool, are, good(20))
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
    }

    func testBelowEightyPercentIsNotEnough() {
        var pool = LearningPool.initial(at: now)
        answer(&pool, .group(.are, .presente), good(15) + Array(repeating: .again, count: 5))
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
    }

    func testLookedUpAnswersCountHalf() {
        var pool = LearningPool.initial(at: now)
        // 12 Good + 8 looked up = 16 of 20 points.
        answer(&pool, .group(.are, .presente), good(12) + Array(repeating: .correct, count: 8))
        XCTAssertFalse(pool.finishLesson(at: now).isEmpty)
        var other = LearningPool.initial(at: now)
        // 11 Good + 9 looked up = 15.5 of 20.
        answer(&other, .group(.are, .presente), good(11) + Array(repeating: .correct, count: 9))
        XCTAssertTrue(other.finishLesson(at: now).isEmpty)
    }

    func testEveryPersonNeedsTwoAnswers() {
        var pool = LearningPool.initial(at: now)
        for _ in 0..<20 { pool.record(.pattern(PatternKey(family: .are, tense: .presente, person: 0)), .good) }
        XCTAssertEqual(pool.progress(of: .group(.are, .presente)).missingPersons, [1, 2, 3, 4, 5])
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
    }

    func testFewerThanTwoAnswersPerPersonAreNotEnough() {
        var pool = LearningPool.initial(at: now)
        answer(&pool, .group(.are, .presente), good(11))
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
        var twice = LearningPool.initial(at: now)
        answer(&twice, .group(.are, .presente), good(12))
        XCTAssertFalse(twice.finishLesson(at: now).isEmpty)
    }

    func testALaterTenseOpensOnlyThroughTheSameGroup() {
        var pool = LearningPool(units: [.group(.are, .presente), .group(.are, .passatoprossimo), .group(.ere, .presente)], at: now)
        answer(&pool, .group(.are, .presente), good(20))
        _ = pool.finishLesson(at: now)
        // -are · Passato prossimo brings -are · Imperfetto, not -ere · Passato prossimo …
        answer(&pool, .group(.are, .passatoprossimo), good(20))
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.group(.are, .imperfetto)])
        // … that comes from -ere · Presente, together with the next group in the Presente.
        answer(&pool, .group(.ere, .presente), good(20))
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.group(.ire, .presente), .group(.ere, .passatoprossimo)])
    }

    func testTheLastGroupOnlyBringsItsNextTense() {
        var pool = LearningPool(units: [.group(.isc, .presente)], at: now)
        answer(&pool, .group(.isc, .presente), good(20))
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.group(.isc, .passatoprossimo)])
    }

    func testAnIrregularVerbBringsTheNextOneAndLaterItsNextTense() {
        var pool = LearningPool.initial(at: now)
        answer(&pool, .irregular("essere", .presente), good(20))
        // No regular group has the Passato prossimo yet, so only the next irregular verb comes.
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.irregular("avere", .presente)])
        // Once -are reaches the Passato prossimo, essere follows.
        answer(&pool, .group(.are, .presente), good(20))
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit),
                       [.group(.ere, .presente), .group(.are, .passatoprossimo), .irregular("essere", .passatoprossimo)])
    }

    func testALaterTenseWaitsForEarlierTensesToPerformWellAgain() {
        // -are · Presente passed once, then slipped to 75 %; -are · Passato prossimo is at 85 %.
        var pool = LearningPool.initial(at: now)
        answer(&pool, .group(.are, .presente), good(20))
        _ = pool.finishLesson(at: now)
        answer(&pool, .group(.are, .presente), good(15) + Array(repeating: .again, count: 5))
        let passato = PoolUnit.group(.are, .passatoprossimo)
        answer(&pool, passato, good(17) + Array(repeating: .again, count: 3))
        XCTAssertTrue(pool.progress(of: passato).performsWell)
        XCTAssertEqual(pool.blockers(of: passato), [.group(.are, .presente)])
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
        XCTAssertFalse(pool.progress(of: passato).passed)

        // 15 Good answers leave all 5 mistakes in the last 20: still below 80 %.
        answer(&pool, .group(.are, .presente), good(15))
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
        // One more and the Presente is back at 80 %: the Passato prossimo unlocks its next steps.
        answer(&pool, .group(.are, .presente), good(1))
        XCTAssertTrue(pool.blockers(of: passato).isEmpty)
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.group(.are, .imperfetto)])
    }

    func testOnlyTheSameGroupOrVerbHoldsBack() {
        var pool = LearningPool(units: [.group(.are, .presente), .group(.ere, .presente), .group(.ere, .passatoprossimo),
                                        .irregular("essere", .presente)], at: now)
        answer(&pool, .group(.are, .presente), good(20))
        answer(&pool, .irregular("essere", .presente), Array(repeating: .again, count: 20))
        // -ere · Passato prossimo waits for -ere · Presente, not for -are or essere.
        XCTAssertEqual(pool.blockers(of: .group(.ere, .passatoprossimo)), [.group(.ere, .presente)])
        // A first tense is never held back.
        XCTAssertTrue(pool.blockers(of: .group(.ere, .presente)).isEmpty)
    }

    func testAnIrregularVerbWaitsForItsOwnEarlierTenses() {
        var pool = LearningPool(units: [.irregular("essere", .presente), .irregular("essere", .passatoprossimo),
                                        .group(.are, .presente)], at: now)
        answer(&pool, .irregular("essere", .presente), good(10) + Array(repeating: .again, count: 10))
        answer(&pool, .irregular("essere", .passatoprossimo), good(20))
        XCTAssertEqual(pool.blockers(of: .irregular("essere", .passatoprossimo)), [.irregular("essere", .presente)])
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
    }

    func testIrregularVerbsFollowThePathOrder() {
        let irregular = Curriculum.irregularVerbs(in: .presente)
        XCTAssertEqual(Array(irregular.prefix(5)), ["essere", "avere", "fare", "andare", "stare"])
        var pool = LearningPool(units: [.irregular("essere", .presente), .irregular("avere", .presente)], at: now)
        answer(&pool, .irregular("essere", .presente), good(20))
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.irregular("fare", .presente)])
    }

    func testAVerbStartsInItsFirstIrregularTense() {
        var pool = LearningPool(units: [.irregular("fare", .presente), .irregular("fare", .passatoprossimo)], at: now)
        answer(&pool, .irregular("fare", .presente), good(20))
        answer(&pool, .irregular("fare", .passatoprossimo), good(20))
        // venire and dire come later in the Presente; the Passato prossimo goes on with vedere (visto, but vedo).
        let added = pool.finishLesson(at: now).map(\.unit)
        XCTAssertTrue(added.contains(.irregular("vedere", .passatoprossimo)))
        XCTAssertFalse(added.contains(.irregular("venire", .passatoprossimo)))
        XCTAssertFalse(added.contains(.irregular("dire", .passatoprossimo)))
    }

    func testAGroupInALaterTenseOnlyAsksAboutVerbsMetInThePresente() {
        var pool = LearningPool(units: [.group(.ire, .presente), .group(.ire, .imperfetto)], at: now)
        // venire is regular in the Imperfetto (venivo), but not met yet: it is irregular in the Presente.
        XCTAssertTrue(PoolUnit.group(.ire, .imperfetto).verbs.contains("venire"))
        XCTAssertFalse(pool.verbs(of: .group(.ire, .imperfetto)).contains("venire"))
        XCTAssertTrue(pool.verbs(of: .group(.ire, .imperfetto)).contains("dormire"))
        pool = LearningPool(units: pool.units + [.irregular("venire", .presente)], at: now)
        XCTAssertTrue(pool.verbs(of: .group(.ire, .imperfetto)).contains("venire"))
    }

    func testLessonFillsWithDifferentVerbsAndMixes() {
        var rng = SeededGenerator(state: 7)
        let pool = LearningPool.initial(at: now - 2 * 86_400)
        for _ in 0..<20 {
            let picked = Curriculum.pickLesson(units: pool.units, verbs: \.verbs, memory: LearningMemory(),
                                               length: 10, at: now, using: &rng)
            XCTAssertEqual(picked.count, 10)
            XCTAssertEqual(Set(picked).count, 10)
            let regular = picked.filter { $0.verb != "essere" }
            XCTAssertEqual(Set(regular.map(\.verb)).count, regular.count) // a different -are verb each time
            XCTAssertLessThanOrEqual(regular.count, 5)
        }
        // A long lesson repeats -are patterns with other verbs to fill up.
        let long = Curriculum.pickLesson(units: pool.units, verbs: \.verbs, memory: LearningMemory(),
                                         length: 20, at: now, using: &rng)
        XCTAssertEqual(long.count, 20)
        XCTAssertEqual(Set(long).count, 20)
    }

    func testAWeakPersonIsTrainedMore() {
        var rng = SeededGenerator(state: 3)
        let pool = LearningPool.initial(at: now - 2 * 86_400)
        var memory = LearningMemory()
        for unit in pool.units {
            for key in unit.keys { memory.record(key, key.person == 3 ? .again : .good, at: now) } // noi is weak
        }
        var noi = 0, total = 0
        for _ in 0..<50 {
            let picked = Curriculum.pickLesson(units: pool.units, verbs: \.verbs, memory: memory,
                                               length: 10, at: now, using: &rng)
            noi += picked.filter { $0.person == 3 }.count
            total += picked.count
        }
        XCTAssertGreaterThan(Double(noi) / Double(total), 0.18) // a sixth would be even
    }

    func testPoolRoundTripsThroughJSON() throws {
        var pool = LearningPool.initial(at: now)
        answer(&pool, .group(.are, .presente), good(20))
        _ = pool.finishLesson(at: now)
        XCTAssertEqual(try JSONDecoder().decode(LearningPool.self, from: JSONEncoder().encode(pool)), pool)
    }
}
