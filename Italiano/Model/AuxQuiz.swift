import Foundation
import Observation

/// One question of the Essere o avere? quiz: a verb and a person.
struct AuxItem: Hashable {
    let verb: String
    let person: Int

    /// Identifies the question in the summary's list of missed forms.
    var key: String { "\(verb)|\(person)" }
    var correctAuxiliary: Auxiliary { VerbLibrary.verb(verb).auxiliary }
    var correctForm: String { Conjugator.auxiliaryForm(correctAuxiliary, person: person) }
    /// essere always on top, avere always below.
    var options: [String] { [Conjugator.esserePresente[person], Conjugator.averePresente[person]] }
    /// The complete form, e.g. "siamo arrivati". The prompt only shows the dictionary form of the
    /// participle, since an agreeing ending (arrivati, arrivata) would give essere away.
    var fullForm: String { VerbLibrary.verb(verb).italian(.passatoprossimo, person) }
}

/// The Essere o avere? quiz: for each verb and person, pick the auxiliary's form in the Passato prossimo.
/// After every choice the complete form is read aloud.
@Observable
final class AuxQuiz: Identifiable {
    private let store: ProgressStore
    private let speech: Speaking

    private(set) var rounds = LessonRounds<AuxItem>([])
    /// The option the learner tapped for the current question, once answered.
    private(set) var chosen: String?
    /// Increases with every question shown, so a pending move to the next one can tell it is too late.
    private var questionNumber = 0

    var phase: LessonPhase { rounds.phase }
    var current: AuxItem? { rounds.current }
    var isAnswered: Bool { chosen != nil }
    var answeredWrong: Bool { chosen != nil && chosen != current?.correctForm }

    init(store: ProgressStore, speech: Speaking = SilentSpeech()) {
        self.store = store
        self.speech = speech
        start()
    }

    static func pool(verbs: Set<String>) -> [AuxItem] {
        VerbLibrary.orderedKeys.filter(verbs.contains).flatMap { verb in
            (0..<6).map { AuxItem(verb: verb, person: $0) }
        }
    }

    func start() {
        let pool = Self.pool(verbs: store.aux.verbs).shuffled()
        rounds = LessonRounds(Array(pool.prefix(store.aux.length.resolve(poolSize: pool.count))))
        showQuestion()
    }

    func choose(_ option: String) {
        guard let item = current, chosen == nil else { return }
        chosen = option
        let ok = option == item.correctForm
        // Only first attempts count for the level.
        if rounds.isFirstAttempt { store.recordAuxAnswer(verb: item.verb, correct: ok) }
        if ok {
            rounds.recordCorrect()
            // The next question waits a moment, so the green answer can be seen, and for the spoken form too.
            let question = questionNumber
            speech.speak(item.fullForm, atLeast: rounds.pauseAfterRight) { [weak self] in
                guard let self, self.questionNumber == question else { return }
                self.next()
            }
        } else {
            rounds.recordMiss(key: item.key, label: "\(Pronoun.italian[item.person]) · \(item.verb)", answer: item.fullForm)
            // A wrong answer waits for "Weiter".
            speech.speak(item.fullForm)
        }
    }

    func next() {
        rounds.advance()
        showQuestion()
    }

    func startNextRound() {
        rounds.startNextRound()
        showQuestion()
    }

    /// Resets the per-question state for whatever `rounds` shows now.
    private func showQuestion() {
        speech.stop()
        chosen = nil
        questionNumber += 1
    }
}
