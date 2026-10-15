import XCTest
@testable import Italiano

final class AuxQuizTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "AuxQuizTests")
        defaults.removePersistentDomain(forName: "AuxQuizTests")
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
