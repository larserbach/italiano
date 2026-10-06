import Foundation

/// How a first answer went.
enum Rating: String, Codable {
    /// Wrong, or the learner asked for the answer.
    case again
    /// Right, but after looking up the verb or the tense.
    case correct
    /// Right without any help.
    case good

    /// For progress toward performing well: a looked-up answer counts half.
    var goodPoints: Double {
        switch self {
        case .again: 0
        case .correct: 0.5
        case .good: 1
        }
    }
}

/// Difficulty, stability and retrievability of one thing being learned.
struct MemoryState: Codable, Equatable {
    /// 1 (easy) … 10 (hard).
    var difficulty: Double
    /// Days until retrievability halves.
    var stability: Double
    /// Chance of recalling it right after `last`; it fades with `stability`.
    var retrievability: Double
    var last: Date
    var lastRating: Rating
    var answers: Int
    var good: Int

    static func days(from start: Date, to end: Date) -> Double { max(0, end.timeIntervalSince(start) / 86_400) }

    func retrievability(at now: Date) -> Double {
        retrievability * pow(2, -Self.days(from: last, to: now) / stability)
    }

    /// Again lowers stability strongly and retrievability moderately; Correct changes neither;
    /// Good raises stability moderately (more after a gap, less when difficult) and retrievability strongly.
    static func updated(_ state: MemoryState?, _ rating: Rating, at now: Date) -> MemoryState {
        guard var state else {
            switch rating {
            case .again:
                return MemoryState(difficulty: 6.5, stability: 0.3, retrievability: 0.3, last: now, lastRating: .again, answers: 1, good: 0)
            case .correct:
                return MemoryState(difficulty: 5.5, stability: 0.5, retrievability: 0.6, last: now, lastRating: .correct, answers: 1, good: 0)
            case .good:
                return MemoryState(difficulty: 4.5, stability: 1, retrievability: 0.9, last: now, lastRating: .good, answers: 1, good: 1)
            }
        }
        let current = state.retrievability(at: now)
        switch rating {
        case .again:
            state.stability = max(0.2, state.stability * 0.4)
            state.retrievability = current * 0.7
            state.difficulty = min(10, state.difficulty + 1.5)
            state.last = now
        case .correct:
            break
        case .good:
            state.stability *= 1 + (0.25 + 0.8 * (1 - current)) * (11 - state.difficulty) / 6
            state.retrievability = current + 0.8 * (1 - current)
            state.difficulty = max(1, state.difficulty - 0.5)
            state.last = now
            state.good += 1
        }
        state.lastRating = rating
        state.answers += 1
        return state
    }
}

/// One verb in one tense.
struct Cell: Hashable, Codable {
    let verb: String
    let tense: Tense
}

/// One verb in one tense for one person.
struct FormKey: Hashable, Codable {
    let verb: String
    let tense: Tense
    let person: Int

    var cell: Cell { Cell(verb: verb, tense: tense) }
}

/// Verb families for the learning path: the regular ending groups, and the irregular verbs.
enum VerbFamily: String, Codable, CaseIterable {
    case are, ere, ire, isc, irregular

    /// The regular groups in the order they join the pool.
    static let regular: [VerbFamily] = [.are, .ere, .ire, .isc]

    init(verb: String) {
        let entry = VerbLibrary.verb(verb)
        if entry.isIrregular {
            self = .irregular
            return
        }
        switch entry.group {
        case .are: self = .are
        case .ere: self = .ere
        case .ire: self = .ire
        case .ireIsc: self = .isc
        }
    }

    var label: String {
        switch self {
        case .are: "-are"
        case .ere: "-ere"
        case .ire: "-ire"
        case .isc: "-ire (isc)"
        case .irregular: "unregelmäßig"
        }
    }

    /// The family's verbs in path order.
    var verbs: [String] { Curriculum.verbOrder.filter { VerbFamily(verb: $0) == self } }
}

/// What the pool is made of: a whole regular group in one tense, or one irregular verb in one tense.
enum PoolUnit: Hashable, Codable {
    case group(VerbFamily, Tense)
    case irregular(String, Tense)

    init(verb: String, tense: Tense) {
        let family = VerbFamily(verb: verb)
        self = family == .irregular ? .irregular(verb, tense) : .group(family, tense)
    }

    var tense: Tense {
        switch self {
        case .group(_, let tense), .irregular(_, let tense): tense
        }
    }

    /// "-are" or the irregular verb.
    var name: String {
        switch self {
        case .group(let family, _): family.label
        case .irregular(let verb, _): verb
        }
    }

    var label: String { "\(name) · \(tense.label)" }

    /// The verbs this unit asks about.
    var verbs: [String] {
        switch self {
        case .group(let family, let tense): family.verbs.filter { VerbLibrary.verb($0).hasTense(tense) }
        case .irregular(let verb, _): [verb]
        }
    }

    /// The persons that exist in this tense (for an irregular verb: that the verb has).
    var persons: [Int] {
        switch self {
        case .group(_, let tense): Array(tense.persons)
        case .irregular(let verb, let tense): tense.persons.filter { VerbLibrary.verb(verb).hasForm(tense, $0) }
        }
    }

    /// Everything that is measured for picking: one key per person.
    var keys: [MemoryKey] {
        switch self {
        case .group(let family, let tense): persons.map { .pattern(PatternKey(family: family, tense: tense, person: $0)) }
        case .irregular(let verb, let tense): persons.map { .form(FormKey(verb: verb, tense: tense, person: $0)) }
        }
    }
}

/// A regular group's ending pattern for one tense and person ("-are · Presente · tu"), shared by all its verbs.
struct PatternKey: Hashable, Codable {
    let family: VerbFamily
    let tense: Tense
    let person: Int
}

/// What a single answer is measured on: the group pattern for regular verbs, the form itself for irregular ones.
enum MemoryKey: Hashable {
    case pattern(PatternKey)
    case form(FormKey)

    init(verb: String, tense: Tense, person: Int) {
        let family = VerbFamily(verb: verb)
        self = family == .irregular
            ? .form(FormKey(verb: verb, tense: tense, person: person))
            : .pattern(PatternKey(family: family, tense: tense, person: person))
    }

    var unit: PoolUnit {
        switch self {
        case .pattern(let key): .group(key.family, key.tense)
        case .form(let key): .irregular(key.verb, key.tense)
        }
    }

    var tense: Tense {
        switch self {
        case .pattern(let key): key.tense
        case .form(let key): key.tense
        }
    }

    var person: Int {
        switch self {
        case .pattern(let key): key.person
        case .form(let key): key.person
        }
    }
}

/// Difficulty, stability and retrievability per regular group pattern and per irregular form.
/// Single regular verbs are not tracked: what counts is whether the learner can conjugate the group.
struct LearningMemory: Codable, Equatable {
    var patterns: [PatternKey: MemoryState] = [:]
    var irregularForms: [FormKey: MemoryState] = [:]

    subscript(key: MemoryKey) -> MemoryState? {
        get {
            switch key {
            case .pattern(let pattern): patterns[pattern]
            case .form(let form): irregularForms[form]
            }
        }
        set {
            switch key {
            case .pattern(let pattern): patterns[pattern] = newValue
            case .form(let form): irregularForms[form] = newValue
            }
        }
    }

    mutating func record(_ key: MemoryKey, _ rating: Rating, at now: Date) {
        self[key] = MemoryState.updated(self[key], rating, at: now)
    }
}
