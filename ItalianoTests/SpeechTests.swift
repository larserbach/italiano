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
        store.conjugation.mode = .free
        store.conjugation.verbs = ["parlare"]
        store.conjugation.tenses = [.presente]
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
