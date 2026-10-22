import XCTest
@testable import Italiano

/// Records what would be spoken; finishes only when the test says so.
private final class FakeSpeech: Speaking {
    var spoken: [String] = []
    var pending: [() -> Void] = []

    func speak(_ text: String, completion: @escaping () -> Void) {
        spoken.append(text)
        pending.append(completion)
    }

    func stop() {
        let finished = pending
        pending = []
        finished.forEach { $0() }
    }

    func finish() { stop() }
}

final class SpeechTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "speech-\(UUID().uuidString)")
    }

    private func makeLesson() -> (ConjugationLesson, FakeSpeech) {
        let store = makeStore(defaults)
        let speech = FakeSpeech()
        return (ConjugationLesson(store: store, speech: speech), speech)
    }

    func testWrongAnswerSpeaksTheFormWithoutPronoun() throws {
        let (lesson, speech) = makeLesson()
        let item = try XCTUnwrap(lesson.current)
        lesson.submit("xyz")
        XCTAssertEqual(speech.spoken, [item.answer])
        XCTAssertFalse(speech.spoken[0].hasPrefix(item.pronoun + " "))
    }

    func testRevealSpeaksTheForm() throws {
        let (lesson, speech) = makeLesson()
        let item = try XCTUnwrap(lesson.current)
        lesson.reveal()
        XCTAssertEqual(speech.spoken, [item.answer])
    }

    func testRightAnswerWaitsForTheSpeechBeforeTheNextCard() throws {
        let (lesson, speech) = makeLesson()
        let item = try XCTUnwrap(lesson.current)
        let card = lesson.cardNumber
        lesson.submit(item.answer)
        XCTAssertEqual(speech.spoken, [item.answer])

        // The 0.6 s pause is over, but the form is still being spoken.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertEqual(lesson.cardNumber, card)

        speech.finish()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(lesson.cardNumber, card + 1)
    }

    private func makeQuiz() -> (AuxQuiz, FakeSpeech) {
        let store = makeStore(defaults)
        store.aux.verbs = ["arrivare"]
        let speech = FakeSpeech()
        return (AuxQuiz(store: store, speech: speech), speech)
    }

    func testAuxQuizSpeaksTheFullFormAfterAWrongChoice() throws {
        let (quiz, speech) = makeQuiz()
        let item = try XCTUnwrap(quiz.current)
        quiz.choose(Conjugator.averePresente[item.person])
        XCTAssertEqual(speech.spoken, [item.fullForm])

        // "Weiter" stops the form if it is still being spoken.
        quiz.next()
        XCTAssertTrue(speech.pending.isEmpty)
    }

    func testAuxQuizWaitsForTheSpeechBeforeTheNextQuestion() throws {
        let (quiz, speech) = makeQuiz()
        let item = try XCTUnwrap(quiz.current)
        quiz.choose(item.correctForm)
        XCTAssertEqual(speech.spoken, [item.fullForm])

        // The 0.6 s pause is over, but the form is still being spoken.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertEqual(quiz.current, item)
        XCTAssertTrue(quiz.isAnswered)

        speech.finish()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNotEqual(quiz.current, item)
        XCTAssertFalse(quiz.isAnswered)
    }

    func testSwitchedOffSpeechFinishesRightAway() {
        let speech = SystemSpeech { false }
        let done = expectation(description: "completion")
        speech.speak("parlo") { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    func testReadAloudIsOnByDefaultAndSaved() {
        XCTAssertTrue(makeStore(defaults).readAloud)
        makeStore(defaults).readAloud = false
        XCTAssertFalse(makeStore(defaults).readAloud)
    }
}
