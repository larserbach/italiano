import Foundation

struct MissedForm: Identifiable {
    let id: String
    let label: String
    let answer: String
    var misses: Int
}

enum LessonPhase { case question, roundComplete, summary }

/// Round bookkeeping shared by both exercises. Mistakes are
/// collected and repeated in a new round once the current one is through, until everything is right.
struct LessonRounds<Item> {
    private var queue: [Item]
    private var roundMissed: [Item] = []
    private var missed: [String: MissedForm] = [:]

    private(set) var phase: LessonPhase = .question
    private(set) var current: Item?
    private(set) var round = 1
    private(set) var roundTotal: Int
    private(set) var roundAnswered = 0
    private(set) var roundCorrect = 0
    let totalPlanned: Int

    var roundMissedCount: Int { roundMissed.count }
    var firstTryCorrect: Int { totalPlanned - missed.count }
    var accuracy: Int { AnswerCounts(correct: firstTryCorrect, mistakes: missed.count).accuracy ?? 0 }
    var missedForms: [MissedForm] { missed.values.sorted { $0.misses > $1.misses } }

    init(_ items: [Item]) {
        queue = items
        roundTotal = items.count
        totalPlanned = items.count
        advance()
    }

    mutating func recordCorrect() {
        roundAnswered += 1
        roundCorrect += 1
    }

    /// `retry` comes back in the next round; the form is listed in the summary under `key`.
    mutating func recordMiss(retry: Item, key: String, label: String, answer: String) {
        roundAnswered += 1
        roundMissed.append(retry)
        missed[key, default: MissedForm(id: key, label: label, answer: answer, misses: 0)].misses += 1
    }

    /// Shows the next item, or ends the round when there is none.
    mutating func advance() {
        guard !queue.isEmpty else {
            current = nil
            phase = roundMissed.isEmpty ? .summary : .roundComplete
            return
        }
        current = queue.removeFirst()
        phase = .question
    }

    mutating func startNextRound() {
        round += 1
        queue = roundMissed.shuffled()
        roundMissed = []
        roundTotal = queue.count
        roundAnswered = 0
        roundCorrect = 0
        advance()
    }
}
