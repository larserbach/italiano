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
}

@Observable
final class AuxQuiz {
    enum Phase { case question, roundComplete, summary }

    private let store: ProgressStore
    private var queue: [AuxItem] = []
    private var roundMissed: [AuxItem] = []
    private var missed: [String: MissedForm] = [:]

    private(set) var phase: Phase = .question
    private(set) var current: AuxItem?
    /// The option the learner tapped for the current question, once answered.
    private(set) var chosen: String?
    private(set) var round = 1
    private(set) var roundTotal = 0
    private(set) var roundAnswered = 0
    private(set) var roundCorrect = 0
    private(set) var totalPlanned = 0

    var isAnswered: Bool { chosen != nil }
    var answeredWrong: Bool { chosen != nil && chosen != current?.correctForm }
    var roundMissedCount: Int { roundMissed.count }
    var firstTryCorrect: Int { totalPlanned - missed.count }
    var accuracy: Int { totalPlanned == 0 ? 0 : Int((Double(firstTryCorrect) / Double(totalPlanned) * 100).rounded()) }
    var missedForms: [MissedForm] { missed.values.sorted { $0.misses > $1.misses } }

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
        queue = Array(pool.prefix(store.aux.length.resolve(poolSize: pool.count)))
        roundMissed = []
        missed = [:]
        round = 1
        roundTotal = queue.count
        roundAnswered = 0
        roundCorrect = 0
        totalPlanned = queue.count
        next()
    }

    func choose(_ option: String) {
        guard let item = current, chosen == nil else { return }
        chosen = option
        roundAnswered += 1
        let ok = option == item.correctForm
        store.recordAuxAnswer(verb: item.verb, correct: ok)
        if ok {
            roundCorrect += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.next() }
        } else {
            var retry = item
            retry.firstAttempt = false
            roundMissed.append(retry)
            let answer = "\(item.correctForm) \(VerbLibrary.verb(item.verb).participle)"
            let label = "\(Pronoun.italian[item.person]) · \(item.verb)"
            missed[item.key, default: MissedForm(id: item.key, label: label, answer: answer, misses: 0)].misses += 1
        }
    }

    func next() {
        chosen = nil
        guard !queue.isEmpty else {
            current = nil
            phase = roundMissed.isEmpty ? .summary : .roundComplete
            return
        }
        current = queue.removeFirst()
        phase = .question
    }

    func startNextRound() {
        round += 1
        queue = roundMissed.shuffled()
        roundMissed = []
        roundTotal = queue.count
        roundAnswered = 0
        roundCorrect = 0
        next()
    }
}
