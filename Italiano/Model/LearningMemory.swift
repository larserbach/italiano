import Foundation

/// How a first answer went.
enum Rating: String, Codable {
    /// Wrong, or the learner asked for the answer.
    case again
    /// Right, but after looking up the verb or the tense.
    case correct
    /// Right without any help.
    case good

    /// For lesson readiness: a looked-up answer counts half.
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
}

/// A regular group's ending pattern for one tense and person ("-are · Presente · tu"), shared by all
/// its verbs. In the Passato prossimo the auxiliary matters as well.
struct PatternKey: Hashable, Codable {
    let family: VerbFamily
    let auxiliary: Auxiliary?
    let tense: Tense
    let person: Int

    /// nil for irregular verbs, which share no pattern.
    init?(_ form: FormKey) {
        let family = VerbFamily(verb: form.verb)
        guard family != .irregular else { return nil }
        self.family = family
        auxiliary = form.tense == .passatoprossimo ? VerbLibrary.verb(form.verb).auxiliary : nil
        tense = form.tense
        person = form.person
    }
}

/// Memory on three levels: each form, each verb×tense, and each regular group pattern.
struct LearningMemory: Codable, Equatable {
    var forms: [FormKey: MemoryState] = [:]
    var cells: [Cell: MemoryState] = [:]
    var patterns: [PatternKey: MemoryState] = [:]

    mutating func record(_ form: FormKey, _ rating: Rating, at now: Date) {
        forms[form] = MemoryState.updated(forms[form], rating, at: now)
        cells[form.cell] = MemoryState.updated(cells[form.cell], rating, at: now)
        if let key = PatternKey(form) { patterns[key] = MemoryState.updated(patterns[key], rating, at: now) }
    }

    /// How well a form is known now, 0…1: half the form itself, a quarter its verb×tense and a quarter
    /// its group pattern (for irregular verbs the verb×tense again). A new regular verb is thus partly
    /// known through its group.
    func known(_ form: FormKey, at now: Date) -> Double {
        let own = forms[form]?.retrievability(at: now) ?? 0
        let cell = cells[form.cell]?.retrievability(at: now) ?? 0
        let pattern = PatternKey(form).flatMap { patterns[$0]?.retrievability(at: now) } ?? cell
        return 0.5 * own + 0.25 * cell + 0.25 * pattern
    }
}
