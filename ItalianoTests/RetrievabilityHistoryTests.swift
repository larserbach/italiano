import XCTest
@testable import Italiano

final class RetrievabilityHistoryTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "RetrievabilityHistoryTests")
        defaults.removePersistentDomain(forName: "RetrievabilityHistoryTests")
    }

    private func curves(_ store: ProgressStore, _ unit: PoolUnit) -> [(person: Int, points: [RetrievabilityHistory.Point])] {
        RetrievabilityHistory.curves(of: unit, log: store.log.entries, memory: store.state(of:), until: store.now())
    }

    /// Answers `rating` for `person` of parlare in the Presente, `days` after `start`.
    private func answer(_ store: ProgressStore, _ clock: TestClock, from start: Date, _ days: Double, _ rating: Rating, person: Int = 1) {
        clock.now = start + days * 86_400
        store.record(ConjugationItem(verb: "parlare", tense: .presente, person: person), rating)
    }

    func testCurveJumpsWhereTheMemoryJumpsAndEndsAtItsValueNow() throws {
        let clock = TestClock()
        let store = makeStore(defaults, clock: clock)
        let start = clock.now
        var replay: MemoryState?
        var after: [Double] = []
        for (days, rating) in [(0.0, Rating.good), (1, .again), (3, .good)] {
            answer(store, clock, from: start, days, rating)
            replay = MemoryState.updated(replay, rating, at: clock.now)
            after.append(replay!.retrievability)
        }
        clock.advance(days: 2)

        let curve = try XCTUnwrap(curves(store, .group(.are, .presente)).first)
        XCTAssertEqual(curve.person, 1)
        for (index, days) in [0.0, 1, 3].enumerated() {
            // The last point at an answer's moment is the value right after it.
            let point = try XCTUnwrap(curve.points.last { $0.date == start + days * 86_400 })
            XCTAssertEqual(point.value, after[index], accuracy: 1e-9)
        }
        let key = MemoryKey(verb: "parlare", tense: .presente, person: 1)
        XCTAssertEqual(curve.points.last?.date, clock.now)
        XCTAssertEqual(try XCTUnwrap(curve.points.last).value, try XCTUnwrap(store.state(of: key)).retrievability(at: clock.now), accuracy: 1e-9)
        XCTAssertTrue(curve.points.allSatisfy { (0...1).contains($0.value) })
    }

    func testACorrectAnswerLeavesTheCurveRunning() throws {
        let clock = TestClock()
        let store = makeStore(defaults, clock: clock)
        let start = clock.now
        answer(store, clock, from: start, 0, .good)
        answer(store, clock, from: start, 1, .correct)
        clock.advance(days: 1)

        let curve = try XCTUnwrap(curves(store, .group(.are, .presente)).first)
        let atAnswer = curve.points.filter { $0.date == start + 86_400 }.map(\.value)
        XCTAssertGreaterThan(atAnswer.count, 1)
        XCTAssertEqual(try XCTUnwrap(atAnswer.max()), try XCTUnwrap(atAnswer.min()), accuracy: 1e-9)
    }

    func testOnlyPersonsWithAnswersHaveACurve() {
        let clock = TestClock()
        let store = makeStore(defaults, clock: clock)
        answer(store, clock, from: clock.now, 0, .good, person: 3)
        answer(store, clock, from: clock.now, 0, .good, person: 0)
        store.record(ConjugationItem(verb: "essere", tense: .presente, person: 2), .good)

        XCTAssertEqual(curves(store, .group(.are, .presente)).map(\.person), [0, 3])
        XCTAssertEqual(curves(store, .irregular("essere", .presente)).map(\.person), [2])
    }

    func testValuesBetweenPointsAreInterpolated() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let points = [RetrievabilityHistory.Point(date: start, value: 1), .init(date: start + 10, value: 0.5)]
        XCTAssertEqual(RetrievabilityHistory.value(at: start + 5, in: points), 0.75)
        XCTAssertEqual(RetrievabilityHistory.value(at: start + 10, in: points), 0.5)
        XCTAssertNil(RetrievabilityHistory.value(at: start - 1, in: points))
        XCTAssertNil(RetrievabilityHistory.value(at: start + 11, in: points))
    }
}
