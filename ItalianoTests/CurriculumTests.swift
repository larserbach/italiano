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

    func testRegularVerbsCountForTheirGroupPattern() {
        var memory = LearningMemory()
        memory.record(MemoryKey(verb: "parlare", tense: .presente, person: 1), .good, at: now)
        memory.record(MemoryKey(verb: "abitare", tense: .presente, person: 1), .again, at: now)
        let pattern = PatternKey(family: .are, tense: .presente, person: 1)
        XCTAssertEqual(memory.patterns.count, 1)
        XCTAssertEqual(memory.patterns[pattern]?.answers, 2)
        XCTAssertEqual(memory.patterns[pattern]?.lastRating, .again)
        XCTAssertTrue(memory.irregularForms.isEmpty)
    }

    func testIrregularVerbsAreTrackedPerForm() {
        var memory = LearningMemory()
        memory.record(MemoryKey(verb: "essere", tense: .presente, person: 0), .good, at: now)
        memory.record(MemoryKey(verb: "avere", tense: .presente, person: 0), .good, at: now)
        XCTAssertTrue(memory.patterns.isEmpty)
        XCTAssertEqual(memory.irregularForms.count, 2)
    }

    func testKeysBelongToTheirUnit() {
        XCTAssertEqual(MemoryKey(verb: "arrivare", tense: .passatoprossimo, person: 3).unit, .group(.are, .passatoprossimo))
        XCTAssertEqual(MemoryKey(verb: "capire", tense: .futuro, person: 0).unit, .group(.isc, .futuro))
        XCTAssertEqual(MemoryKey(verb: "fare", tense: .presente, person: 2).unit, .irregular("fare", .presente))
        XCTAssertEqual(PoolUnit.irregular("potere", .imperativo).persons, [])
        XCTAssertEqual(PoolUnit.group(.are, .imperativo).persons, [1, 2, 3, 4, 5])
    }

    func testMemoryRoundTripsThroughJSON() throws {
        var memory = LearningMemory()
        memory.record(MemoryKey(verb: "parlare", tense: .passatoprossimo, person: 2), .again, at: now)
        memory.record(MemoryKey(verb: "fare", tense: .presente, person: 2), .good, at: now)
        XCTAssertEqual(try JSONDecoder().decode(LearningMemory.self, from: JSONEncoder().encode(memory)), memory)
    }
}

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
        XCTAssertEqual(Set(store.unlockedVerbs), Set(VerbFamily.are.verbs + ["essere"]))
        XCTAssertEqual(store.unlockedVerbs.count, 21)
        XCTAssertEqual(store.unlockedTenses, [.presente])
    }

    func testTheWindowKeepsTheLastTwentyAnswers() {
        var pool = LearningPool.initial(at: now)
        let are = PoolUnit.group(.are, .presente)
        answer(&pool, are, Array(repeating: .again, count: 10) + good(20))
        XCTAssertEqual(pool.progress(of: are).answers, 20)
        XCTAssertEqual(pool.progress(of: are).share, 1)
    }

    func testAWindowSavedWithFortyAnswersCountsOnlyTheLastTwenty() throws {
        var window = LearningPool.Window()
        for index in 0..<40 { window.append(index < 20 ? .again : .good, person: index % 6) }
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(window)) as? [String: Any])
        saved["ratings"] = Array(repeating: "again", count: 20) + Array(repeating: "good", count: 20)
        saved["persons"] = (0..<40).map { $0 % 6 }
        var old = try JSONDecoder().decode(LearningPool.Window.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertEqual(old.share, 1)
        XCTAssertEqual(old.recentRatings.count, 20)
        old.append(.again, person: 0)
        XCTAssertEqual(old.ratings.count, 20)
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

    func testFewerThanTwentyAnswersAreNotEnough() {
        var pool = LearningPool.initial(at: now)
        answer(&pool, .group(.are, .presente), good(19))
        XCTAssertTrue(pool.finishLesson(at: now).isEmpty)
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
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.group(.ere, .passatoprossimo), .group(.are, .imperfetto)])
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
        let irregular = VerbFamily.irregular.verbs
        XCTAssertEqual(Array(irregular.prefix(5)), ["essere", "avere", "fare", "andare", "stare"])
        var pool = LearningPool(units: [.irregular("essere", .presente), .irregular("avere", .presente)], at: now)
        answer(&pool, .irregular("essere", .presente), good(20))
        XCTAssertEqual(pool.finishLesson(at: now).map(\.unit), [.irregular("fare", .presente)])
    }

    func testLessonFillsWithDifferentVerbsAndMixes() {
        var rng = SeededGenerator(state: 7)
        let pool = LearningPool.initial(at: now - 2 * 86_400)
        for _ in 0..<20 {
            let picked = Curriculum.pickLesson(units: pool.units, verbs: \.verbs, pool: pool, memory: LearningMemory(),
                                               length: 10, at: now, using: &rng)
            XCTAssertEqual(picked.count, 10)
            XCTAssertEqual(Set(picked).count, 10)
            let regular = picked.filter { $0.verb != "essere" }
            XCTAssertEqual(Set(regular.map(\.verb)).count, regular.count) // a different -are verb each time
            XCTAssertLessThanOrEqual(regular.count, 5)
        }
        // A long lesson repeats -are patterns with other verbs to fill up.
        let long = Curriculum.pickLesson(units: pool.units, verbs: \.verbs, pool: pool, memory: LearningMemory(),
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
            let picked = Curriculum.pickLesson(units: pool.units, verbs: \.verbs, pool: pool, memory: memory,
                                               length: 10, at: now, using: &rng)
            noi += picked.filter { $0.person == 3 }.count
            total += picked.count
        }
        XCTAssertGreaterThan(Double(noi) / Double(total), 0.18) // a sixth would be even
    }

    func testFreePracticeKeepsToTheChosenVerbsAndTenses() {
        let store = makeStore(defaults)
        let picked = store.pickLesson(length: 10, verbs: ["parlare", "abitare"], tenses: [.presente])
        XCTAssertFalse(picked.isEmpty)
        XCTAssertTrue(picked.allSatisfy { ["parlare", "abitare"].contains($0.verb) && $0.tense == .presente })
    }

    func testPoolRoundTripsThroughJSON() throws {
        var pool = LearningPool.initial(at: now)
        answer(&pool, .group(.are, .presente), good(20))
        _ = pool.finishLesson(at: now)
        XCTAssertEqual(try JSONDecoder().decode(LearningPool.self, from: JSONEncoder().encode(pool)), pool)
    }
}

final class MigrationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "MigrationTests")
        defaults.removePersistentDomain(forName: "MigrationTests")
    }

    func testEarlierCellsBecomeGroupsAndIrregularVerbs() throws {
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "cells": [["verb": "parlare", "tense": "presente"], ["verb": "abitare", "tense": "presente"],
                      ["verb": "capire", "tense": "passatoprossimo"], ["verb": "fare", "tense": "presente"]],
        ]), forKey: "coniugazione-pool")
        defaults.set(Data("{}".utf8), forKey: "coniugazione-dsr-memory")
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.units, [.group(.are, .presente), .irregular("essere", .presente),
                                          .group(.isc, .passatoprossimo), .irregular("fare", .presente)])
        XCTAssertNil(defaults.data(forKey: "coniugazione-pool"))
        XCTAssertNil(defaults.data(forKey: "coniugazione-dsr-memory"))
        XCTAssertEqual(makeStore(defaults).pool.units, store.pool.units)
    }

    func testTheFirstLearningPathCarriesOverToo() throws {
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "unlocked": [["verb": "parlare", "tense": "presente"], ["verb": "credere", "tense": "presente"]],
            "frontier": "credere",
        ]), forKey: "coniugazione-curriculum")
        XCTAssertEqual(makeStore(defaults).pool.units, [.group(.are, .presente), .irregular("essere", .presente),
                                                        .group(.ere, .presente)])
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
        // Another -are verb, same pattern: it continues where parlare left off.
        store.record(ConjugationItem(verb: "abitare", tense: .presente, person: 1), .correct)

        let entries = AnswerLog(fileURL: url).entries
        XCTAssertEqual(entries.map(\.rating), [.again, .correct])
        XCTAssertEqual(entries.map(\.verb), ["parlare", "abitare"])
        XCTAssertNil(entries[0].stabilityBefore)
        XCTAssertEqual(entries[1].stabilityBefore, entries[0].stabilityAfter)
        XCTAssertEqual(entries[1].stabilityAfter, entries[0].stabilityAfter) // Correct changes nothing
        XCTAssertEqual(store.log.entries(for: "parlare").count, 1)

        // Over the cap, the oldest lines are dropped on load.
        let line = String(data: try JSONEncoder().encode(entries[1]), encoding: .utf8)! + "\n"
        try String(repeating: line, count: AnswerLog.maxEntries + 5).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(AnswerLog(fileURL: url).entries.count, AnswerLog.maxEntries)

        store.resetProgress()
        XCTAssertTrue(store.log.entries.isEmpty)
        XCTAssertTrue(AnswerLog(fileURL: url).entries.isEmpty)
    }
}
