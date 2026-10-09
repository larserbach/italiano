import XCTest
@testable import Italiano

final class AnswerCheckTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "answer-check-\(UUID().uuidString)")
    }

    private func check(_ guess: String, _ verb: String, _ tense: Tense, _ person: Int, _ gender: Gender? = nil) -> AnswerCheck {
        AnswerCheck(guess, for: ConjugationItem(verb: verb, tense: tense, person: person, gender: gender))
    }

    func testRightAnswers() {
        XCTAssertEqual(check("parlo", "parlare", .presente, 0), .right)
        XCTAssertEqual(check("  Parlerò ", "parlare", .futuro, 0), .right)
        XCTAssertEqual(check("vai", "andare", .imperativo, 1), .right)
        XCTAssertEqual(check("", "parlare", .presente, 0), .wrong)
    }

    func testMissingOrWrongAccentsAreAlmost() {
        XCTAssertEqual(check("parlero", "parlare", .futuro, 0), .almost)
        XCTAssertEqual(check("parleró", "parlare", .futuro, 0), .almost)
        XCTAssertEqual(check("e arrivato", "arrivare", .passatoprossimo, 2, .masculine), .almost)
        XCTAssertEqual(check("puo", "potere", .presente, 2), .almost)
    }

    func testOneLetterTyposAreAlmost() {
        XCTAssertEqual(check("parlaimo", "parlare", .presente, 3), .almost)
        XCTAssertEqual(check("parliamoo", "parlare", .presente, 3), .almost)
        XCTAssertEqual(check("parlamo", "parlare", .presente, 3), .almost)
        XCTAssertEqual(check("ho parlatto", "parlare", .passatoprossimo, 0, .masculine), .almost)
        XCTAssertEqual(check("parlerro", "parlare", .futuro, 0), .almost)
        XCTAssertEqual(check("parlammo", "parlare", .presente, 3), .wrong, "two letters off")
    }

    func testOtherFormsOfTheVerbStayWrong() {
        XCTAssertEqual(check("parli", "parlare", .presente, 0), .wrong)
        XCTAssertEqual(check("parlera", "parlare", .futuro, 0), .wrong)
        XCTAssertEqual(check("parlavo", "parlare", .imperfetto, 2), .wrong)
        XCTAssertEqual(check("ha parlato", "parlare", .passatoprossimo, 0, .feminine), .wrong)
        XCTAssertEqual(check("sono arrivata", "arrivare", .passatoprossimo, 0, .masculine), .wrongGender)
    }

    func testShortAnswersOnlyForgiveAccents() {
        XCTAssertEqual(check("fo", "fare", .presente, 2), .wrong)
        XCTAssertEqual(check("da", "dare", .presente, 2), .almost)
    }

    func testSpellingTrapsStayWrong() {
        XCTAssertEqual(check("mancero", "mancare", .futuro, 0), .wrong)
        XCTAssertEqual(check("mancerò", "mancare", .futuro, 0), .wrong)
        XCTAssertEqual(check("manci", "mancare", .presente, 1), .wrong)
        XCTAssertEqual(check("viaggierò", "viaggiare", .futuro, 0), .wrong)
        XCTAssertEqual(check("viaggii", "viaggiare", .presente, 1), .wrong)
        XCTAssertEqual(check("viaggero", "viaggiare", .futuro, 0), .almost)
    }

    func testAlmostCountsHalfAndIsNotRepeated() throws {
        let store = makeStore(defaults)
        store.conjugation.mode = .free
        store.conjugation.verbs = ["parlare"]
        store.conjugation.tenses = [.presente]
        let lesson = ConjugationLesson(store: store)
        let first = try XCTUnwrap(lesson.current)
        let slip = String(first.answer.dropLast()) + "x"
        XCTAssertEqual(AnswerCheck(slip, for: first), .almost)
        lesson.submit(slip)
        XCTAssertEqual(lesson.feedback, .almost(first.answer))
        XCTAssertEqual(store.log.entries.last?.rating, .correct)
        XCTAssertTrue(lesson.rounds.missedForms.isEmpty)
    }

    func testOneEditApart() {
        XCTAssertTrue(AnswerCheck.isOneEditApart("abcd", "abxd"))
        XCTAssertTrue(AnswerCheck.isOneEditApart("abcd", "abdc"))
        XCTAssertTrue(AnswerCheck.isOneEditApart("abcd", "abd"))
        XCTAssertTrue(AnswerCheck.isOneEditApart("abd", "abcd"))
        XCTAssertFalse(AnswerCheck.isOneEditApart("abcd", "abcd"))
        XCTAssertFalse(AnswerCheck.isOneEditApart("abcd", "badc"))
        XCTAssertFalse(AnswerCheck.isOneEditApart("abcd", "ab"))
    }
}
