import Foundation
import Observation

/// One card of a conjugation lesson: a verb in a tense and person, and in the Passato prossimo a gender.
struct ConjugationItem: Hashable {
    let verb: String
    let tense: Tense
    let person: Int
    /// Set for every passato prossimo question, also for verbs with avere where it doesn't
    /// change the answer: showing it only for essere verbs would give away the auxiliary.
    var gender: Gender?
    /// False for the repeat in a later round; only first attempts are recorded.
    var firstAttempt = true

    /// Identifies the form in the summary's list of missed forms.
    var key: String { "\(verb)|\(tense.rawValue)|\(person)|\(gender?.rawValue ?? "")" }
    /// The group (or irregular verb) in that tense this question belongs to.
    var unit: PoolUnit { PoolUnit(verb: verb, tense: tense) }
    var answer: String { VerbLibrary.verb(verb).italian(tense, person, gender: gender) }
    /// The main form plus accepted variants (fa' and fai).
    var accepted: [String] { VerbLibrary.verb(verb).acceptedAnswers(tense, person, gender: gender) }
    var pronoun: String { Pronoun.italian(person, gender: gender) }
    var marker: String? { gender?.marker }

    /// The same form for the other gender, to recognise answers that only miss the agreement.
    var otherGenderAnswer: String? {
        guard let gender, VerbLibrary.verb(verb).isGendered(tense) else { return nil }
        return VerbLibrary.verb(verb).italian(tense, person, gender: gender == .masculine ? .feminine : .masculine)
    }
}

/// One conjugation lesson: picks the cards, checks the answers, records first attempts and reads the
/// right form aloud.
@Observable
final class ConjugationLesson: Identifiable {
    enum Feedback: Equatable {
        case none
        case correct(String)
        /// An accent or one letter off: counts half and comes back in the next round.
        case almost(String)
        case wrong(String)
        /// Right verb form, but for the other gender.
        case wrongGender(String)
        /// The learner asked for the answer ("?"); counts as wrong.
        case revealed(String)
    }

    private let store: ProgressStore
    private let speech: Speaking
    /// Set while a right answer waits for the next card, so pressing Return again does nothing.
    private var busy = false

    private(set) var rounds = LessonRounds<ConjugationItem>([])
    /// Increases with every card shown, so views can reset per card even if an item repeats.
    private(set) var cardNumber = 0
    private(set) var feedback: Feedback = .none
    /// Progress changes and pool additions from round 1; set once round 1 is through.
    private(set) var outcome: LessonOutcome?
    /// Groups and irregular verbs answered for the first time in this lesson, for the "Neu" badge.
    private(set) var newUnits: Set<PoolUnit> = []
    /// Whether the learner opened the verb or tense description on the current card; a right answer then
    /// counts as Correct instead of Good.
    private(set) var lookedUp = false
    /// Shares of Good points when the lesson started, to show what it changed.
    private var sharesBefore: [PoolUnit: Double] = [:]
    /// Units with a first answer in this lesson.
    private var answeredUnits: Set<PoolUnit> = []

    var isPathLesson: Bool { store.conjugation.mode == .path }

    var phase: LessonPhase { rounds.phase }
    var current: ConjugationItem? { rounds.current }

    /// After a slip, a wrong answer or a reveal the card stays until the learner confirms.
    var isReviewing: Bool {
        switch feedback {
        case .almost, .wrong, .wrongGender, .revealed: true
        default: false
        }
    }

    init(store: ProgressStore, speech: Speaking = SilentSpeech()) {
        self.store = store
        self.speech = speech
        start()
    }

    /// The free-practice pool: every form of the selected verbs and tenses that the path has unlocked.
    static func freePool(_ store: ProgressStore) -> [ConjugationItem] {
        pool(verbs: store.conjugation.verbs, tenses: store.conjugation.tenses)
            .filter { store.isUnlocked(verb: $0.verb, tense: $0.tense) }
    }

    static func pool(verbs: Set<String>, tenses: Set<Tense>) -> [ConjugationItem] {
        var pool: [ConjugationItem] = []
        for verb in VerbLibrary.orderedKeys where verbs.contains(verb) {
            for tense in Tense.allCases where tenses.contains(tense) {
                for person in tense.persons where VerbLibrary.verb(verb).hasForm(tense, person) {
                    pool.append(ConjugationItem(verb: verb, tense: tense, person: person))
                }
            }
        }
        return pool
    }

    func start() {
        store.resetLastMistakes()
        outcome = nil
        answeredUnits = []
        let settings = store.conjugation
        let selected: [FormKey]
        switch settings.mode {
        case .path:
            // The path's pool has no fixed size; `pickLesson` stops when it runs out.
            selected = store.pickLesson(length: settings.length.resolve(poolSize: .max))
        case .free:
            selected = store.pickLesson(length: settings.length.resolve(poolSize: Self.freePool(store).count),
                                        verbs: settings.verbs, tenses: settings.tenses)
        }
        let units = Set(selected.map { PoolUnit(verb: $0.verb, tense: $0.tense) })
        newUnits = units.filter { store.progress(of: $0).answers == 0 }
        sharesBefore = Dictionary(uniqueKeysWithValues: units.compactMap { unit in store.progress(of: unit).share.map { (unit, $0) } })
        let chosen = selected.shuffled().map { form -> ConjugationItem in
            var item = ConjugationItem(verb: form.verb, tense: form.tense, person: form.person)
            if item.tense == .passatoprossimo { item.gender = Gender.allCases.randomElement() }
            return item
        }
        rounds = LessonRounds(chosen)
        startCard()
    }

    func submit(_ guess: String) {
        guard let item = current, !busy else { return }
        // On a card held for review, Return confirms like "Verstanden".
        if isReviewing {
            nextCard()
            return
        }
        busy = true
        let check = AnswerCheck(guess, for: item)
        if item.firstAttempt {
            let rating: Rating = switch check {
            case .right: lookedUp ? .correct : .good
            case .almost: .correct
            case .wrong, .wrongGender: .again
            }
            recordFirstAttempt(item, rating)
        }

        switch check {
        case .right:
            rounds.recordCorrect()
            feedback = .correct(item.answer)
            // The next card waits a moment, so the green answer can be seen, and for the spoken form too.
            let card = cardNumber
            speech.speak(item.answer, atLeast: 0.6) { [weak self] in
                guard let self, self.cardNumber == card else { return }
                self.nextCard()
            }
        case .almost, .wrong, .wrongGender:
            recordMiss(item)
            feedback = switch check {
            case .almost: .almost(item.answer)
            case .wrongGender: .wrongGender(item.answer)
            default: .wrong(item.answer)
            }
            busy = false
            speech.speak(item.answer)
        }
    }

    func reveal() {
        guard let item = current, !busy, !isReviewing else { return }
        if item.firstAttempt { recordFirstAttempt(item, .again) }
        recordMiss(item)
        feedback = .revealed(item.answer)
        speech.speak(item.answer)
    }

    /// The learner opened the verb or tense description while answering.
    func noteLookup() {
        guard current != nil, !isReviewing else { return }
        lookedUp = true
    }

    func startNextRound() {
        rounds.startNextRound()
        startCard()
    }

    // MARK: Private

    private func nextCard() {
        rounds.advance()
        startCard()
    }

    /// Resets the per-card state for whatever `rounds` shows now.
    private func startCard() {
        speech.stop()
        busy = false
        feedback = .none
        lookedUp = false
        if current != nil { cardNumber += 1 }
        // Only round 1 counts for the pool, so what it unlocks is settled as soon as round 1 is through.
        if rounds.round == 1, phase != .question, outcome == nil {
            outcome = store.finishLesson(practised: answeredUnits, before: sharesBefore)
        }
    }

    private func recordFirstAttempt(_ item: ConjugationItem, _ rating: Rating) {
        store.record(item, rating)
        answeredUnits.insert(item.unit)
    }

    private func recordMiss(_ item: ConjugationItem) {
        var retry = item
        retry.firstAttempt = false
        let pronoun = item.marker.map { "\(item.pronoun) (\($0))" } ?? item.pronoun
        rounds.recordMiss(retry: retry, key: item.key,
                          label: "\(pronoun) · \(item.verb) · \(item.tense.label)", answer: item.answer)
    }
}

/// What round 1 of a conjugation lesson changed.
struct LessonOutcome {
    /// A unit's share of Good points in its last answers, before and after the lesson.
    struct ProgressChange: Identifiable {
        let unit: PoolUnit
        let from: Double?
        let to: Double?
        var id: PoolUnit { unit }
    }

    let changes: [ProgressChange]
    let additions: [LearningPool.Addition]
}
