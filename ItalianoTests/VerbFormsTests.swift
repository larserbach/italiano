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
