import Foundation
import Observation

struct ConjugationItem: Hashable {
    enum Side: Hashable { case italian, german }

    let verb: String
    let tense: Tense
    let person: Int
    var shown: Side = .italian
    var firstAttempt = true

    var key: String { "\(verb)|\(tense.rawValue)|\(person)" }
    var answer: String { VerbLibrary.verb(verb).italian(tense, person) }
}

struct MissedForm: Identifiable {
    let id: String
    let label: String
    let answer: String
    var misses: Int
}

/// Rounds work like the prototype: mistakes are collected and repeated in a
/// new round once the current one is through, until everything is right.
@Observable
final class ConjugationLesson {
    enum Phase { case question, roundComplete, summary }

    enum Feedback: Equatable {
        case none
        case correct(String)
        case wrong(String)
        case revealed(String)
    }

    private let store: ProgressStore
    private var queue: [ConjugationItem] = []
    private var roundMissed: [ConjugationItem] = []
    private var missed: [String: MissedForm] = [:]
    private var busy = false

    private(set) var phase: Phase = .question
    private(set) var current: ConjugationItem?
    /// Increases with every card shown, so views can reset per card even if an item repeats.
    private(set) var cardNumber = 0
    private(set) var feedback: Feedback = .none
    private(set) var round = 1
    private(set) var roundTotal = 0
    private(set) var roundAnswered = 0
    private(set) var roundCorrect = 0
    private(set) var totalPlanned = 0

    /// After a wrong answer or a reveal the card stays until the learner confirms.
    var isReviewing: Bool {
        switch feedback {
        case .wrong, .revealed: true
        default: false
        }
    }

    var roundMissedCount: Int { roundMissed.count }
    var firstTryCorrect: Int { totalPlanned - missed.count }
    var accuracy: Int { totalPlanned == 0 ? 0 : Int((Double(firstTryCorrect) / Double(totalPlanned) * 100).rounded()) }
    var missedForms: [MissedForm] { missed.values.sorted { $0.misses > $1.misses } }

    init(store: ProgressStore) {
        self.store = store
        start()
    }

    static func pool(verbs: Set<String>, tenses: Set<Tense>) -> [ConjugationItem] {
        var pool: [ConjugationItem] = []
        for verb in VerbLibrary.orderedKeys where verbs.contains(verb) {
            for tense in Tense.allCases where tenses.contains(tense) {
                for person in tense.persons {
                    pool.append(ConjugationItem(verb: verb, tense: tense, person: person))
                }
            }
        }
        return pool
    }

    func start() {
        store.resetLastMistakes()
        let settings = store.conjugation
        let pool = Self.pool(verbs: settings.verbs, tenses: settings.tenses)
        let count = settings.length.resolve(poolSize: pool.count)
        let chosen = weightedSample(pool, count: count).shuffled().map { item -> ConjugationItem in
            var item = item
            item.shown = pickSide(settings.direction)
            return item
        }
        queue = chosen
        roundMissed = []
        missed = [:]
        round = 1
        roundTotal = chosen.count
        roundAnswered = 0
        roundCorrect = 0
        totalPlanned = chosen.count
        nextCard()
    }

    func submit(_ guess: String) {
        guard let item = current, !busy else { return }
        if isReviewing {
            nextCard()
            return
        }
        busy = true
        let ok = !normalize(guess).isEmpty && normalize(guess) == normalize(item.answer)
        roundAnswered += 1
        if item.firstAttempt { store.recordFirstAttempt(verb: item.verb, correct: ok) }

        if ok {
            roundCorrect += 1
            feedback = .correct(item.answer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.nextCard() }
        } else {
            recordMiss(item)
            feedback = .wrong(item.answer)
            busy = false
        }
    }

    func reveal() {
        guard let item = current, !busy, !isReviewing else { return }
        roundAnswered += 1
        if item.firstAttempt { store.recordFirstAttempt(verb: item.verb, correct: false) }
        recordMiss(item)
        feedback = .revealed(item.answer)
    }

    func startNextRound() {
        round += 1
        queue = roundMissed.shuffled()
        roundMissed = []
        roundTotal = queue.count
        roundAnswered = 0
        roundCorrect = 0
        nextCard()
    }

    // MARK: Private

    private func nextCard() {
        busy = false
        feedback = .none
        guard !queue.isEmpty else {
            current = nil
            phase = roundMissed.isEmpty ? .summary : .roundComplete
            return
        }
        current = queue.removeFirst()
        cardNumber += 1
        phase = .question
    }

    private func recordMiss(_ item: ConjugationItem) {
        var retry = item
        retry.firstAttempt = false
        roundMissed.append(retry)
        let label = "\(Pronoun.italian[item.person]) · \(item.verb) · \(item.tense.label)"
        missed[item.key, default: MissedForm(id: item.key, label: label, answer: item.answer, misses: 0)].misses += 1
    }

    private func pickSide(_ direction: Direction) -> ConjugationItem.Side {
        switch direction {
        case .italian: .italian
        case .german: .german
        case .mixed: Bool.random() ? .italian : .german
        }
    }

    /// Weighted sampling without replacement: level 0 verbs are five times as likely as mastered ones.
    private func weightedSample(_ pool: [ConjugationItem], count: Int) -> [ConjugationItem] {
        guard count < pool.count else { return pool }
        let scored = pool.map { item -> (ConjugationItem, Double) in
            let weight = 1 + Double(ProgressStore.maxLevel - store.level(of: item.verb)) * 0.4
            return (item, pow(Double.random(in: 0..<1), 1 / weight))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(count).map(\.0)
    }
}

func normalize(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}
