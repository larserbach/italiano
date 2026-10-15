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
        store.conjugation.mode = .free
        store.conjugation.verbs = ["parlare"]
        store.conjugation.tenses = [.presente]
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
        XCTAssertTrue(store.isRecentMistake(verb: "parlare", tenses: [.presente]))
        XCTAssertFalse(store.isRecentMistake(verb: "parlare", tenses: [.imperfetto]))

        lesson.startNextRound()
        XCTAssertEqual(lesson.rounds.round, 2)
        XCTAssertFalse(lesson.current!.firstAttempt)
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
        store.practise("parlare", .presente, answers: 10) // half the window, all Good
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 5)
        XCTAssertEqual(store.level(of: "abitare", tense: .presente), 5) // same group
        XCTAssertEqual(store.level(of: "credere", tense: .presente), 0) // not in the pool
        store.practise("parlare", .presente, answers: 10)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 10)
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente, .imperfetto]), 5)
    }

    func testOlderProgressKeysAreRemoved() throws {
        defaults.set(try JSONEncoder().encode(["parlare": 7]), forKey: "coniugazione-levels")
        defaults.set(try JSONEncoder().encode(["parlare": ["presente": 3]]), forKey: "coniugazione-tense-levels")
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.units, LearningPool.startUnits)
        XCTAssertNil(defaults.data(forKey: "coniugazione-levels"))
        XCTAssertNil(defaults.data(forKey: "coniugazione-tense-levels"))
    }

    func testGenderIsSetForEveryPassatoProssimo() {
        seedPool([("parlare", .presente), ("parlare", .passatoprossimo),
                        ("arrivare", .presente), ("arrivare", .passatoprossimo)], in: defaults)
        let store = makeStore(defaults)
        store.conjugation.mode = .free
        store.conjugation.verbs = ["arrivare", "parlare"]
        store.conjugation.tenses = [.passatoprossimo, .presente]
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

    func testOtherGenderAnswerGetsSpecificFeedback() throws {
        seedPool([("tornare", .presente), ("tornare", .passatoprossimo)], in: defaults)
        let store = makeStore(defaults)
        store.conjugation.mode = .free
        store.conjugation.verbs = ["tornare"]
        store.conjugation.tenses = [.passatoprossimo]
        let lesson = ConjugationLesson(store: store)
        let item = try XCTUnwrap(lesson.current)
        let other = try XCTUnwrap(item.otherGenderAnswer)
        XCTAssertNotEqual(other, item.answer)
        lesson.submit(other)
        XCTAssertEqual(lesson.feedback, .wrongGender(item.answer))
        XCTAssertTrue(lesson.isReviewing)
    }

    func testAuxQuizRecordsAgreedForm() {
        let store = makeStore(defaults)
        store.aux.verbs = ["arrivare"]
        store.aux.length = .all
        let quiz = AuxQuiz(store: store)
        while let item = quiz.current, quiz.phase == .question {
            quiz.choose(Conjugator.averePresente[item.person])
            quiz.next()
        }
        let answers = Set(quiz.rounds.missedForms.map(\.answer))
        XCTAssertTrue(answers.contains("siamo arrivati"))
        XCTAssertFalse(answers.contains("siamo arrivato"))
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

    func testAuxQuizMarksWrongChoice() {
        let store = makeStore(defaults)
        store.aux.verbs = ["arrivare"]
        let quiz = AuxQuiz(store: store)
        let item = quiz.current!
        XCTAssertEqual(item.correctForm, Conjugator.esserePresente[item.person])
        quiz.choose(Conjugator.averePresente[item.person])
        XCTAssertTrue(quiz.answeredWrong)
        XCTAssertEqual(quiz.rounds.roundMissedCount, 1)
    }

    func testAuxQuizCountsFirstAttemptsOnly() {
        let store = makeStore(defaults)
        store.aux.verbs = ["arrivare"]
        store.aux.length = .count(1)
        let quiz = AuxQuiz(store: store)
        quiz.choose(Conjugator.averePresente[quiz.current!.person])
        quiz.next()
        XCTAssertEqual(quiz.phase, .roundComplete)
        quiz.startNextRound()
        quiz.choose(quiz.current!.correctForm) // correct in the repeat round
        XCTAssertEqual(store.auxLevel(of: "arrivare"), 0)
    }
}
