import Foundation
@testable import Italiano

/// Stores a learning pool with the groups and irregular verbs of these verbs, so the next `ProgressStore` on
/// `defaults` starts from it.
func seedPool(_ cells: [(String, Tense)], in defaults: UserDefaults) {
    let pool = LearningPool(units: cells.map { PoolUnit(verb: $0.0, tense: $0.1) }, at: Date(timeIntervalSinceReferenceDate: 800_000_000))
    defaults.set(try! JSONEncoder().encode(pool), forKey: "coniugazione-group-pool")
}

/// A clock the tests move forward by hand.
final class TestClock {
    var now: Date

    init(now: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) { self.now = now }

    func advance(days: Double) { now += days * 86_400 }
}

/// A store without files on disk unless URLs are given, driven by `clock`.
func makeStore(_ defaults: UserDefaults, clock: TestClock = TestClock(),
               historyURL: URL? = nil, logURL: URL? = nil) -> ProgressStore {
    ProgressStore(defaults: defaults, historyURL: historyURL, logURL: logURL, now: { clock.now })
}

/// A random number generator with a fixed sequence.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension ProgressStore {
    /// A lesson on one verb in one tense: `answers` first attempts with `rating`, going round the persons,
    /// then the end of round 1.
    @discardableResult
    func practise(_ verb: String, _ tense: Tense, rating: Rating = .good, answers: Int = 6) -> LessonOutcome {
        let unit = PoolUnit(verb: verb, tense: tense)
        let before = progress(of: unit).share.map { [unit: $0] } ?? [:]
        for index in 0..<answers {
            record(ConjugationItem(verb: verb, tense: tense, person: unit.persons[index % unit.persons.count]), rating)
        }
        return finishLesson(practised: [unit], before: before)
    }
}
