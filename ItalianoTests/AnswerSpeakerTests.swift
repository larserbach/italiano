import XCTest
@testable import Italiano

/// Records what would be spoken; finishes only when the test says so.
private final class FakeSpeaker: AnswerSpeaking {
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

final class AnswerSpeakerTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "answer-speaker-\(UUID().uuidString)")
    }

    private func makeLesson(speakAnswers: Bool = true) -> (ConjugationLesson, FakeSpeaker) {
        let store = makeStore(defaults)
        store.conjugation.mode = .free
        store.conjugation.verbs = ["parlare"]
        store.conjugation.tenses = [.presente]
        store.conjugation.speakAnswers = speakAnswers
        let speaker = FakeSpeaker()
        return (ConjugationLesson(store: store, speaker: speaker), speaker)
    }

    func testWrongAnswerSpeaksTheFormWithoutPronoun() throws {
        let (lesson, speaker) = makeLesson()
        let item = try XCTUnwrap(lesson.current)
        lesson.submit("xyz")
        XCTAssertEqual(speaker.spoken, [item.answer])
        XCTAssertFalse(speaker.spoken[0].hasPrefix(item.pronoun + " "))
    }

    func testRevealSpeaksTheForm() throws {
        let (lesson, speaker) = makeLesson()
        let item = try XCTUnwrap(lesson.current)
        lesson.reveal()
        XCTAssertEqual(speaker.spoken, [item.answer])
    }

    func testRightAnswerWaitsForTheSpeechBeforeTheNextCard() throws {
        let (lesson, speaker) = makeLesson()
        let item = try XCTUnwrap(lesson.current)
        let card = lesson.cardNumber
        lesson.submit(item.answer)
        XCTAssertEqual(speaker.spoken, [item.answer])

        // The 0.6 s pause is over, but the form is still being spoken.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertEqual(lesson.cardNumber, card)

        speaker.finish()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(lesson.cardNumber, card + 1)
    }

    func testSwitchedOffSpeaksNothing() throws {
        let (lesson, speaker) = makeLesson(speakAnswers: false)
        let item = try XCTUnwrap(lesson.current)
        lesson.submit("xyz")
        lesson.submit("")
        lesson.submit(lesson.current?.answer ?? item.answer)
        XCTAssertTrue(speaker.spoken.isEmpty)
    }

    func testOlderSettingsLoadWithSpeechOn() throws {
        var settings = ProgressStore.ConjugationSettings()
        settings.speakAnswers = false
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertNotNil(json.removeValue(forKey: "speakAnswers"))
        settings = try JSONDecoder().decode(ProgressStore.ConjugationSettings.self,
                                            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(settings.speakAnswers)
    }
}
