import XCTest
@testable import Italiano

final class LessonTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "LessonTests")
        defaults.removePersistentDomain(forName: "LessonTests")
    }

    func testWrongAnswerIsRepeatedInNextRound() {
        let store = makeStore(defaults)
        store.conjugation.length = .count(5)
        let lesson = ConjugationLesson(store: store)
        XCTAssertEqual(lesson.rounds.roundTotal, 5)

        let firstVerb = lesson.current!.verb
        lesson.submit("sbagliato")
        XCTAssertTrue(lesson.isReviewing)
        lesson.submit("") // "Verstanden"
        for _ in 0..<4 { lesson.reveal(); lesson.submit("") }

        XCTAssertEqual(lesson.phase, .roundComplete)
        XCTAssertEqual(lesson.rounds.roundMissedCount, 5)
        XCTAssertEqual(store.level(of: firstVerb, tense: .presente), 0)

        lesson.startNextRound()
        XCTAssertEqual(lesson.rounds.round, 2)
        XCTAssertFalse(lesson.rounds.isFirstAttempt)
    }

    func testEveryFirstAnswerUpdatesMemoryRightAway() {
        let store = makeStore(defaults)
        let lesson = ConjugationLesson(store: store)
        // Nothing has been answered yet, so every group and irregular verb in the lesson is new.
        XCTAssertTrue(lesson.newUnits.contains(lesson.current!.unit))
        let first = lesson.current!
        lesson.submit("sbagliato")
        XCTAssertEqual(store.state(of: MemoryKey(verb: first.verb, tense: first.tense, person: first.person))?.lastRating, .again)
        XCTAssertEqual(store.progress(of: first.unit).answers, 1)
        XCTAssertEqual(store.log.entries.count, 1)
        XCTAssertNil(lesson.outcome)
        lesson.submit("") // Verstanden
        for _ in 0..<4 { lesson.reveal(); lesson.submit("") }

        // Round 1 is over: every practised unit is new and reported with its share now.
        XCTAssertEqual(lesson.phase, .roundComplete)
        let outcome = try! XCTUnwrap(lesson.outcome)
        XCTAssertFalse(outcome.changes.isEmpty)
        XCTAssertTrue(outcome.changes.allSatisfy { $0.from == nil && $0.to == 0 })
        XCTAssertTrue(outcome.additions.isEmpty)
        let answers = { store.pool.units.map { store.progress(of: $0).answers }.reduce(0, +) }
        XCTAssertEqual(answers(), 5)

        // Retry rounds do not count.
        lesson.startNextRound()
        lesson.reveal()
        XCTAssertEqual(answers(), 5)
    }

    func testLookingSomethingUpMakesARightAnswerCorrectInsteadOfGood() {
        let store = makeStore(defaults)
        let lesson = ConjugationLesson(store: store)
        let first = lesson.current!
        lesson.noteLookup()
        XCTAssertTrue(lesson.lookedUp)
        lesson.submit(first.answer)
        XCTAssertTrue(lesson.countsHalf)
        XCTAssertEqual(store.state(of: MemoryKey(verb: first.verb, tense: first.tense, person: first.person))?.lastRating, .correct)
        XCTAssertEqual(store.log.entries.last?.rating, .correct)
    }

    func testRightAnswerWithoutHelpIsGood() {
        let store = makeStore(defaults)
        let lesson = ConjugationLesson(store: store)
        let first = lesson.current!
        lesson.submit(first.answer)
        XCTAssertEqual(store.state(of: MemoryKey(verb: first.verb, tense: first.tense, person: first.person))?.lastRating, .good)
    }

    func testRingsShowProgressTowardPerformingWell() {
        let store = makeStore(defaults)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 0)
        store.practise("parlare", .presente, answers: 6) // one of the two answers per person, all Good
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 5)
        XCTAssertEqual(store.level(of: "abitare", tense: .presente), 5) // same group
        XCTAssertEqual(store.level(of: "credere", tense: .presente), 0) // not in the pool
        store.practise("parlare", .presente, answers: 6)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 10)
    }

    func testGenderIsSetForEveryPassatoProssimo() {
        seedPool([("parlare", .presente), ("parlare", .passatoprossimo),
                        ("arrivare", .presente), ("arrivare", .passatoprossimo)], in: defaults)
        let store = makeStore(defaults)
        store.conjugation.length = .count(20)
        let lesson = ConjugationLesson(store: store)
        var seen: [ConjugationItem] = []
        while let item = lesson.current, lesson.phase == .question {
            seen.append(item)
            lesson.reveal(); lesson.submit("")
        }
        XCTAssertEqual(seen.count, 20)
        for item in seen {
            // Also for parlare (avere), so the m/f hint doesn't give away the auxiliary.
            XCTAssertEqual(item.gender != nil, item.tense == .passatoprossimo, "\(item.key)")
        }
        let parlare = seen.first { $0.verb == "parlare" && $0.tense == .passatoprossimo && $0.person == 0 }
        if let parlare { XCTAssertEqual(parlare.answer, "ho parlato") }
    }

    func testRoundOneRecordsWhatEachAnswerDidToItsForm() throws {
        seedPool([("parlare", .presente)], in: defaults)
        let store = makeStore(defaults)
        store.conjugation.length = .count(6) // every person of -are once
        let lesson = ConjugationLesson(store: store)
        for _ in 0..<6 { lesson.reveal(); lesson.submit("") }
        XCTAssertEqual(lesson.phase, .roundComplete)
        XCTAssertEqual(lesson.answeredForms.count, 6)
        XCTAssertTrue(lesson.answeredForms.allSatisfy { $0.before == nil && abs($0.after - 0.3) < 1e-9 })

        // The repeat rounds change nothing.
        lesson.startNextRound()
        let repeated = try XCTUnwrap(lesson.current)
        lesson.submit(repeated.answer)
        XCTAssertEqual(lesson.answeredForms.count, 6)

        // The next lesson starts its own list: a wrong answer lowers a known form, a right one raises it.
        lesson.start()
        XCTAssertTrue(lesson.answeredForms.isEmpty)
        let first = try XCTUnwrap(lesson.current)
        lesson.reveal(); lesson.submit("")
        lesson.submit(try XCTUnwrap(lesson.current).answer)
        let (wrong, right) = (lesson.answeredForms[0], lesson.answeredForms[1])
        XCTAssertEqual(wrong.label, "\(first.pronoun) · \(first.verb) · Pres.")
        XCTAssertLessThan(wrong.after, try XCTUnwrap(wrong.before))
        XCTAssertGreaterThan(right.after, try XCTUnwrap(right.before))
    }

    func testTrendsFollowTheRoundedPercentages() {
        XCTAssertEqual(Trend(from: 0.45, to: 0.5), .up)
        XCTAssertEqual(Trend(from: 0.5, to: 0.25), .down)
        XCTAssertEqual(Trend(from: 0.451, to: 0.449), .same) // both 45 %
        XCTAssertNil(Trend(from: nil, to: 0.3)) // new
    }

    func testOtherGenderAnswerGetsSpecificFeedback() throws {
        // Only essere in the Passato prossimo, so every card agrees with a gender (sono stato / stata).
        seedPool([("essere", .passatoprossimo)], in: defaults)
        let store = makeStore(defaults)
        let lesson = ConjugationLesson(store: store)
        let item = try XCTUnwrap(lesson.current)
        let other = try XCTUnwrap(item.otherGenderAnswer)
        XCTAssertNotEqual(other, item.answer)
        lesson.submit(other)
        XCTAssertEqual(lesson.feedback, .wrongGender(item.answer))
        XCTAssertTrue(lesson.isReviewing)
    }
}
