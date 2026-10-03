import XCTest
@testable import Italiano

/// Every form the app derives must match what the HTML prototype produced.
final class VerbFormsTests: XCTestCase {
    private typealias Fixture = [String: [String: [String: [String?]]]]

    func testAllFormsMatchPrototype() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "prototype-forms", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))

        XCTAssertEqual(Set(fixture.keys), Set(VerbLibrary.orderedKeys.filter { !VerbLibrary.verb($0).isIrregular }))
        for (key, languages) in fixture {
            let verb = VerbLibrary.verb(key)
            for tense in Tense.allCases {
                XCTAssertEqual(verb.italian[tense], languages["it"]?[tense.rawValue], "\(key) \(tense) it")
                XCTAssertEqual(verb.german[tense], languages["de"]?[tense.rawValue], "\(key) \(tense) de")
            }
        }
    }

    func testImperativeHasNoIoForm() {
        let pool = ConjugationLesson.pool(verbs: ["parlare"], tenses: [.imperativo, .presente])
        XCTAssertEqual(pool.count, 11)
        XCTAssertFalse(pool.contains { $0.tense == .imperativo && $0.person == 0 })
    }

    func testSpellingNotesCoverSpecialVerbs() {
        XCTAssertEqual(VerbLibrary.verb("viaggiare").spellingNote,
                       "Das i macht nur das g weich. Vor i und e fällt es weg: tu viaggi, noi viaggiamo, viaggerò, che loro viaggino.")
        XCTAssertTrue(VerbLibrary.verb("sciare").spellingNote?.contains("tu scii, scierò, che loro sciino") == true)
        XCTAssertTrue(VerbLibrary.verb("mancare").spellingNote?.contains("tu manchi, mancherò") == true)
        XCTAssertNil(VerbLibrary.verb("parlare").spellingNote)
        let withNotes = VerbLibrary.orderedKeys.filter { VerbLibrary.verb($0).spellingNote != nil }
        XCTAssertEqual(Set(withNotes), ["viaggiare", "passeggiare", "sciare", "mancare"])
    }

    func testEssereParticipleAgreesWithGender() {
        let arrivare = VerbLibrary.verb("arrivare")
        XCTAssertEqual((0..<6).map { arrivare.italian(.passatoprossimo, $0, gender: .feminine) },
                       ["sono arrivata", "sei arrivata", "è arrivata", "siamo arrivate", "siete arrivate", "sono arrivate"])
        XCTAssertEqual(arrivare.italian(.passatoprossimo, 3, gender: .masculine), "siamo arrivati")
        XCTAssertEqual(VerbLibrary.verb("parlare").italian(.passatoprossimo, 2, gender: .feminine), "ha parlato")
        XCTAssertEqual(arrivare.italian(.presente, 0, gender: .feminine), "arrivo")

        let gendered = VerbLibrary.orderedKeys.filter {
            !VerbLibrary.verb($0).isIrregular && VerbLibrary.verb($0).isGendered(.passatoprossimo)
        }
        XCTAssertEqual(Set(gendered), ["arrivare", "diventare", "durare", "entrare", "mancare", "restare",
                                       "sembrare", "tornare", "bastare", "partire"])
        XCTAssertFalse(Tense.allCases.filter { $0 != .passatoprossimo }.contains { arrivare.isGendered($0) })
    }

    func testPronounShowsGender() {
        XCTAssertEqual(Pronoun.italian(2, gender: .feminine), "lei")
        XCTAssertEqual(Pronoun.german(2, gender: .masculine), "er")
        XCTAssertNil(Pronoun.marker(2, gender: .feminine))
        XCTAssertEqual(Pronoun.marker(0, gender: .feminine), "f")
        XCTAssertNil(Pronoun.marker(0, gender: nil))
        XCTAssertEqual(Pronoun.italian(2, gender: nil), "lui/lei")
    }

    func testNormalizeIgnoresCaseAndSpacing() {
        XCTAssertEqual(normalize("  Ho   PARLATO "), "ho parlato")
    }
}

final class LessonTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "LessonTests")
        defaults.removePersistentDomain(forName: "LessonTests")
    }

    func testWrongAnswerIsRepeatedInNextRound() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
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

    func testLevelRisesOnceAtTheEndOfRoundOne() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        let lesson = ConjugationLesson(store: store)
        let first = lesson.current!
        lesson.submit(first.answer.uppercased())
        XCTAssertEqual(lesson.feedback, .correct(first.answer))
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 0) // not per answer
        XCTAssertNil(lesson.outcome)

        // The first answer moves on after a delay; answer the rest directly.
        let expectation = expectation(description: "next card")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
        while let item = lesson.current, lesson.phase == .question {
            lesson.submit(item.answer)
            let next = self.expectation(description: "next")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { next.fulfill() }
            wait(for: [next], timeout: 2)
        }

        XCTAssertEqual(lesson.phase, .summary)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 1)
        XCTAssertEqual(lesson.outcome?.levelChanges.map(\.to), [1])
        XCTAssertNil(lesson.outcome?.unlock)
    }

    func testChipLevelIsAverageRoundedDown() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.raise("parlare", .presente, lessons: 5)
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente]), 5)
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente, .imperfetto]), 2)

        store.raise("parlare", .imperfetto, lessons: 6)
        store.lower("parlare", .presente, lessons: 2)
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente, .imperfetto]), 4) // 3 and 6
    }

    func testLegacyVerbLevelsMoveToPresente() throws {
        defaults.set(try JSONEncoder().encode(["parlare": 7]), forKey: "coniugazione-levels")
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 7)
        XCTAssertEqual(store.level(of: "parlare", tense: .imperfetto), 0)
        XCTAssertNil(defaults.data(forKey: "coniugazione-levels"))
        XCTAssertEqual(ProgressStore(defaults: defaults, historyURL: nil).level(of: "parlare", tense: .presente), 7)
    }

    func testGenderIsSetOnlyWhereItMatters() {
        seedCurriculum([("parlare", .presente), ("parlare", .passatoprossimo),
                        ("arrivare", .presente), ("arrivare", .passatoprossimo)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
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
            let expectsGender = item.verb == "arrivare" && item.tense == .passatoprossimo
            XCTAssertEqual(item.gender != nil, expectsGender, "\(item.key)")
        }
    }

    func testOtherGenderAnswerGetsSpecificFeedback() throws {
        seedCurriculum([("tornare", .presente), ("tornare", .passatoprossimo)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
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
        let store = ProgressStore(defaults: defaults, historyURL: nil)
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
        seedCurriculum([("parlare", .presente), ("parlare", .imperfetto), ("parlare", .congiuntivo)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.conjugation.tenses = [.imperfetto, .congiuntivo]
        store.aux.length = .all
        let reloaded = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(reloaded.conjugation.tenses, [.imperfetto, .congiuntivo])
        XCTAssertEqual(reloaded.aux.length, .all)
    }

    func testResetProgressClearsLevelsMistakesAndHistoryButKeepsSettings() {
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("reset-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyURL) }

        seedCurriculum([("parlare", .presente), ("capire", .presente), ("capire", .futuro)], in: defaults)
        let store = ProgressStore(defaults: defaults, historyURL: historyURL)
        store.conjugation.mode = .free
        store.conjugation.tenses = [.futuro]
        store.conjugation.length = .count(10)
        store.raise("parlare", .presente, lessons: 1)
        store.recordFirstAttempt(verb: "capire", tense: .futuro, correct: false)
        store.recordAuxAnswer(verb: "arrivare", correct: true)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 1)
        XCTAssertTrue(store.isRecentMistake(verb: "capire", tenses: [.futuro]))
        XCTAssertFalse(store.history.isEmpty)

        store.resetProgress()

        for reloaded in [store, ProgressStore(defaults: defaults, historyURL: historyURL)] {
            XCTAssertEqual(reloaded.level(of: "parlare", tense: .presente), 0)
            XCTAssertEqual(reloaded.auxLevel(of: "arrivare"), 0)
            XCTAssertFalse(reloaded.isRecentMistake(verb: "capire", tenses: [.futuro]))
            XCTAssertTrue(reloaded.history.isEmpty)
            XCTAssertEqual(reloaded.curriculum, .initial)
            // Free practice falls back to what is unlocked again; the rest stays.
            XCTAssertEqual(reloaded.conjugation.verbs, ["parlare"])
            XCTAssertEqual(reloaded.conjugation.tenses, [.presente])
            XCTAssertEqual(reloaded.conjugation.mode, .free)
            XCTAssertEqual(reloaded.conjugation.length, .count(10))
        }
    }

    func testFreshInstallStartsWithTheFirstVerbPresenteAndFiveQuestions() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(store.conjugation.verbs, ["parlare"])
        XCTAssertEqual(store.conjugation.tenses, [.presente])
        XCTAssertEqual(store.conjugation.length, .count(5))
        XCTAssertEqual(store.conjugation.mode, .path)
        XCTAssertEqual(store.curriculum, .initial)
    }

    func testSavedSelectionWithoutKnownVerbsFallsBackToTheFirstVerb() throws {
        var settings = ProgressStore.ConjugationSettings()
        settings.verbs = ["xyz"]
        defaults.set(try JSONEncoder().encode(settings), forKey: "coniugazione-settings")
        XCTAssertEqual(ProgressStore(defaults: defaults, historyURL: nil).conjugation.verbs, ["parlare"])
    }

    func testSettingsSavedWithTheOldDirectionStillLoad() throws {
        seedCurriculum([("parlare", .presente), ("parlare", .futuro)], in: defaults)
        var settings = ProgressStore.ConjugationSettings()
        settings.verbs = ["parlare"]
        settings.tenses = [.futuro]
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        saved["direction"] = "mixed"
        saved["mode"] = nil // saved before the learning path existed
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: "coniugazione-settings")

        let store = ProgressStore(defaults: defaults, historyURL: nil)
        XCTAssertEqual(store.conjugation.verbs, ["parlare"])
        XCTAssertEqual(store.conjugation.tenses, [.futuro])
        XCTAssertEqual(store.conjugation.mode, .path)
    }

    func testAuxQuizMarksWrongChoice() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
        store.aux.verbs = ["arrivare"]
        let quiz = AuxQuiz(store: store)
        let item = quiz.current!
        XCTAssertEqual(item.correctForm, Conjugator.esserePresente[item.person])
        quiz.choose(Conjugator.averePresente[item.person])
        XCTAssertTrue(quiz.answeredWrong)
        XCTAssertEqual(quiz.rounds.roundMissedCount, 1)
    }

    func testAuxQuizCountsFirstAttemptsOnly() {
        let store = ProgressStore(defaults: defaults, historyURL: nil)
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
