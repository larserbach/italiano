import XCTest
@testable import Italiano

/// Every form the app derives must match what the HTML prototype produced.
final class VerbFormsTests: XCTestCase {
    private typealias Fixture = [String: [String: [String: [String?]]]]

    func testAllFormsMatchPrototype() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "prototype-forms", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))

        XCTAssertEqual(Set(fixture.keys), Set(VerbLibrary.orderedKeys))
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

        let gendered = VerbLibrary.orderedKeys.filter { VerbLibrary.verb($0).isGendered(.passatoprossimo) }
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
        let store = ProgressStore(defaults: defaults)
        store.conjugation.verbs = ["parlare"]
        store.conjugation.tenses = [.presente]
        store.conjugation.length = .count(5)
        let lesson = ConjugationLesson(store: store)
        XCTAssertEqual(lesson.roundTotal, 5)

        let firstVerb = lesson.current!.verb
        lesson.submit("sbagliato")
        XCTAssertTrue(lesson.isReviewing)
        lesson.submit("") // "Verstanden"
        for _ in 0..<4 { lesson.reveal(); lesson.submit("") }

        XCTAssertEqual(lesson.phase, .roundComplete)
        XCTAssertEqual(lesson.roundMissedCount, 5)
        XCTAssertEqual(store.level(of: firstVerb, tense: .presente), 0)
        XCTAssertTrue(store.isRecentMistake(verb: "parlare", tenses: [.presente]))
        XCTAssertFalse(store.isRecentMistake(verb: "parlare", tenses: [.imperfetto]))

        lesson.startNextRound()
        XCTAssertEqual(lesson.round, 2)
        XCTAssertFalse(lesson.current!.firstAttempt)
    }

    func testCorrectAnswerRaisesLevel() {
        let store = ProgressStore(defaults: defaults)
        store.conjugation.verbs = ["capire"]
        store.conjugation.tenses = [.futuro]
        store.conjugation.direction = .german
        let lesson = ConjugationLesson(store: store)
        let item = lesson.current!
        XCTAssertEqual(item.shown, .german)
        lesson.submit(item.answer.uppercased())
        XCTAssertEqual(lesson.feedback, .correct(item.answer))
        XCTAssertEqual(store.level(of: "capire", tense: .futuro), 1)
        XCTAssertEqual(store.level(of: "capire", tense: .presente), 0)
    }

    func testChipLevelIsAverageRoundedDown() {
        let store = ProgressStore(defaults: defaults)
        for _ in 0..<5 { store.recordFirstAttempt(verb: "parlare", tense: .presente, correct: true) }
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente]), 5)
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente, .imperfetto]), 2)

        for _ in 0..<6 { store.recordFirstAttempt(verb: "parlare", tense: .imperfetto, correct: true) }
        for _ in 0..<2 { store.recordFirstAttempt(verb: "parlare", tense: .presente, correct: false) }
        XCTAssertEqual(store.level(of: "parlare", tenses: [.presente, .imperfetto]), 4) // 3 and 6
    }

    func testLegacyVerbLevelsMoveToPresente() throws {
        defaults.set(try JSONEncoder().encode(["parlare": 7]), forKey: "coniugazione-levels")
        let store = ProgressStore(defaults: defaults)
        XCTAssertEqual(store.level(of: "parlare", tense: .presente), 7)
        XCTAssertEqual(store.level(of: "parlare", tense: .imperfetto), 0)
        XCTAssertNil(defaults.data(forKey: "coniugazione-levels"))
        XCTAssertEqual(ProgressStore(defaults: defaults).level(of: "parlare", tense: .presente), 7)
    }

    func testGenderIsSetOnlyWhereItMatters() {
        let store = ProgressStore(defaults: defaults)
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
        let store = ProgressStore(defaults: defaults)
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
        let store = ProgressStore(defaults: defaults)
        store.aux.verbs = ["arrivare"]
        store.aux.length = .all
        let quiz = AuxQuiz(store: store)
        while let item = quiz.current, quiz.phase == .question {
            quiz.choose(Conjugator.averePresente[item.person])
            quiz.next()
        }
        let answers = Set(quiz.missedForms.map(\.answer))
        XCTAssertTrue(answers.contains("siamo arrivati"))
        XCTAssertFalse(answers.contains("siamo arrivato"))
    }

    func testSettingsPersist() {
        let store = ProgressStore(defaults: defaults)
        store.conjugation.tenses = [.imperfetto, .congiuntivo]
        store.aux.length = .all
        let reloaded = ProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.conjugation.tenses, [.imperfetto, .congiuntivo])
        XCTAssertEqual(reloaded.aux.length, .all)
    }

    func testAuxQuizMarksWrongChoice() {
        let store = ProgressStore(defaults: defaults)
        store.aux.verbs = ["arrivare"]
        let quiz = AuxQuiz(store: store)
        let item = quiz.current!
        XCTAssertEqual(item.correctForm, Conjugator.esserePresente[item.person])
        quiz.choose(Conjugator.averePresente[item.person])
        XCTAssertTrue(quiz.answeredWrong)
        XCTAssertEqual(quiz.roundMissedCount, 1)
    }
}
