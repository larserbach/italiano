import Foundation
import Observation

struct AuxItem: Hashable {
    let verb: String
    let person: Int
    var firstAttempt = true

    var key: String { "\(verb)|\(person)" }
    var correctAuxiliary: Auxiliary { VerbLibrary.verb(verb).auxiliary }
    var correctForm: String { Conjugator.auxiliaryForm(correctAuxiliary, person: person) }
    /// essere always on top, avere always below.
    var options: [String] { [Conjugator.esserePresente[person], Conjugator.averePresente[person]] }
    /// The complete form, e.g. "siamo arrivati". The prompt only shows the dictionary form of the
    /// participle, since an agreeing ending (arrivati, arrivata) would give essere away.
    var fullForm: String { VerbLibrary.verb(verb).italian(.passatoprossimo, person) }
}

@Observable
final class AuxQuiz {
    private let store: ProgressStore

    private(set) var rounds = LessonRounds<AuxItem>([])
    /// The option the learner tapped for the current question, once answered.
    private(set) var chosen: String?

    var phase: LessonPhase { rounds.phase }
    var current: AuxItem? { rounds.current }
    var isAnswered: Bool { chosen != nil }
    var answeredWrong: Bool { chosen != nil && chosen != current?.correctForm }

    init(store: ProgressStore) {
        self.store = store
        start()
    }

    static func pool(verbs: Set<String>) -> [AuxItem] {
        VerbLibrary.orderedKeys.filter(verbs.contains).flatMap { verb in
            (0..<6).map { AuxItem(verb: verb, person: $0) }
        }
    }

    func start() {
        let pool = Self.pool(verbs: store.aux.verbs).shuffled()
        chosen = nil
        rounds = LessonRounds(Array(pool.prefix(store.aux.length.resolve(poolSize: pool.count))))
    }

    func choose(_ option: String) {
        guard let item = current, chosen == nil else { return }
        chosen = option
        let ok = option == item.correctForm
        if item.firstAttempt { store.recordAuxAnswer(verb: item.verb, correct: ok) }
        if ok {
            rounds.recordCorrect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.next() }
        } else {
            var retry = item
            retry.firstAttempt = false
            rounds.recordMiss(retry: retry, key: item.key,
                              label: "\(Pronoun.italian[item.person]) · \(item.verb)", answer: item.fullForm)
        }
    }

    func next() {
        chosen = nil
        rounds.advance()
    }

    func startNextRound() {
        chosen = nil
        rounds.startNextRound()
    }
}
