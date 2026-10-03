import Foundation
@testable import Italiano

/// Stores a learning path with these cells unlocked, so the next `ProgressStore` on `defaults` starts from it.
func seedCurriculum(_ cells: [(String, Tense)], in defaults: UserDefaults) {
    let state = CurriculumState(sanitizing: cells.map { Cell(verb: $0.0, tense: $0.1) })
    defaults.set(try! JSONEncoder().encode(state), forKey: "coniugazione-curriculum")
}

extension ProgressStore {
    /// Plays `lessons` perfect lessons on one cell, one level step each.
    func raise(_ verb: String, _ tense: Tense, lessons: Int) {
        for _ in 0..<lessons {
            _ = finishFirstRound(results: [Cell(verb: verb, tense: tense): AnswerCounts(correct: 3, mistakes: 0)])
        }
    }

    func lower(_ verb: String, _ tense: Tense, lessons: Int) {
        for _ in 0..<lessons {
            _ = finishFirstRound(results: [Cell(verb: verb, tense: tense): AnswerCounts(correct: 0, mistakes: 3)])
        }
    }
}
