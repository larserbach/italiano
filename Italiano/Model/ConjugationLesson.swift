import Foundation
import Observation

struct ConjugationItem: Hashable {
    let verb: String
    let tense: Tense
    let person: Int
    /// Set only when the answer depends on the subject's gender.
    var gender: Gender?
    var firstAttempt = true

    var key: String { "\(verb)|\(tense.rawValue)|\(person)|\(gender?.rawValue ?? "")" }
    var cell: Cell { Cell(verb: verb, tense: tense) }
    var answer: String { VerbLibrary.verb(verb).italian(tense, person, gender: gender) }
    /// The main form plus accepted variants (fa' and fai).
    var accepted: [String] { VerbLibrary.verb(verb).acceptedAnswers(tense, person, gender: gender) }
    var pronoun: String { Pronoun.italian(person, gender: gender) }
    var marker: String? { Pronoun.marker(person, gender: gender) }

    /// The same form for the other gender, to recognise answers that only miss the agreement.
    var otherGenderAnswer: String? {
        guard let gender else { return nil }
        return VerbLibrary.verb(verb).italian(tense, person, gender: gender == .masculine ? .feminine : .masculine)
    }
}

@Observable
final class ConjugationLesson {
    enum Feedback: Equatable {
        case none
        case correct(String)
        case wrong(String)
        /// Right verb form, but for the other gender.
        case wrongGender(String)
        case revealed(String)
    }

    private let store: ProgressStore
    private var busy = false

    private(set) var rounds = LessonRounds<ConjugationItem>([])
    /// Increases with every card shown, so views can reset per card even if an item repeats.
    private(set) var cardNumber = 0
    private(set) var feedback: Feedback = .none
    /// Level changes and the unlock from round 1; set once round 1 is through.
    private(set) var outcome: LessonOutcome?
    /// Cells answered for the first time in this lesson, for the "Neu" badge.
    private(set) var newCells: Set<Cell> = []
    private var firstAnswers: [Cell: AnswerCounts] = [:]

    var isPathLesson: Bool { store.conjugation.mode == .path }

    var phase: LessonPhase { rounds.phase }
    var current: ConjugationItem? { rounds.current }

    /// After a wrong answer or a reveal the card stays until the learner confirms.
    var isReviewing: Bool {
        switch feedback {
        case .wrong, .wrongGender, .revealed: true
        default: false
        }
    }

    init(store: ProgressStore) {
        self.store = store
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
        firstAnswers = [:]
        let settings = store.conjugation
        let selected: [ConjugationItem]
        switch settings.mode {
        case .path:
            selected = Curriculum.composeLesson(store.curriculum, length: settings.length.resolve(poolSize: .max),
                                                level: store.level(of:))
        case .free:
            let pool = Self.freePool(store)
            selected = Curriculum.weightedSample(pool, count: settings.length.resolve(poolSize: pool.count),
                                                 level: { self.store.level(of: $0.cell) })
        }
        newCells = Set(selected.map(\.cell)).filter { !store.history.hasAnswers(verb: $0.verb, tense: $0.tense) }
        let chosen = selected.shuffled().map { item -> ConjugationItem in
            var item = item
            if VerbLibrary.verb(item.verb).isGendered(item.tense) { item.gender = Gender.allCases.randomElement() }
            return item
        }
        rounds = LessonRounds(chosen)
        startCard()
    }

    func submit(_ guess: String) {
        guard let item = current, !busy else { return }
        if isReviewing {
            nextCard()
            return
        }
        busy = true
        let ok = !normalize(guess).isEmpty && item.accepted.contains { normalize($0) == normalize(guess) }
        if item.firstAttempt { recordFirstAttempt(item, correct: ok) }

        if ok {
            rounds.recordCorrect()
            feedback = .correct(item.answer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.nextCard() }
        } else {
            recordMiss(item)
            let genderSlip = item.otherGenderAnswer.map { normalize($0) == normalize(guess) } ?? false
            feedback = genderSlip ? .wrongGender(item.answer) : .wrong(item.answer)
            busy = false
        }
    }

    func reveal() {
        guard let item = current, !busy, !isReviewing else { return }
        if item.firstAttempt { recordFirstAttempt(item, correct: false) }
        recordMiss(item)
        feedback = .revealed(item.answer)
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
        busy = false
        feedback = .none
        if current != nil { cardNumber += 1 }
        if rounds.round == 1, phase != .question, outcome == nil {
            outcome = store.finishFirstRound(results: firstAnswers)
        }
    }

    private func recordFirstAttempt(_ item: ConjugationItem, correct: Bool) {
        store.recordFirstAttempt(verb: item.verb, tense: item.tense, correct: correct)
        firstAnswers[item.cell, default: AnswerCounts()] += AnswerCounts(correct: correct ? 1 : 0, mistakes: correct ? 0 : 1)
    }

    private func recordMiss(_ item: ConjugationItem) {
        var retry = item
        retry.firstAttempt = false
        let pronoun = item.marker.map { "\(item.pronoun) (\($0))" } ?? item.pronoun
        rounds.recordMiss(retry: retry, key: item.key,
                          label: "\(pronoun) · \(item.verb) · \(item.tense.label)", answer: item.answer)
    }
}

func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "’", with: "'")
        .replacingOccurrences(of: "‘", with: "'")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}
