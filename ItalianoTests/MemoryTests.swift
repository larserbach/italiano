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
