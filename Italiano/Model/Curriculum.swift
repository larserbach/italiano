import Foundation

/// What the learner is working on: whole regular groups and single irregular verbs, each in a tense. Whether a
/// verb is irregular is decided per tense: scrivere counts for -ere in the Presente and on its own in the
/// Passato prossimo.
///
/// It starts with all -are verbs and essere in the Presente. A unit that performs well (≥ 80 % Good in its
/// last 20 answers, a looked-up answer counting half, every person answered at least twice) unlocks:
/// a regular group the next group in the same tense and itself in the next tense; an irregular verb the
/// next verb irregular in the same tense, and itself in the next tense it is irregular in once a regular group
/// has that tense.
/// A unit in a later tense only unlocks while the same group or verb still performs well in every earlier
/// tense in the pool.
struct LearningPool: Codable, Equatable {
    /// The last answers of a unit, with the person each was about.
    struct Window: Codable, Equatable {
        private(set) var ratings: [Rating] = []
        private(set) var persons: [Int] = []

        mutating func append(_ rating: Rating, person: Int) {
            ratings.append(rating)
            persons.append(person)
            // A window saved with a larger size shrinks to the current one.
            if ratings.count > Curriculum.windowSize {
                ratings.removeFirst(ratings.count - Curriculum.windowSize)
                persons.removeFirst(persons.count - Curriculum.windowSize)
            }
        }

        /// The answers that count: the last `windowSize`.
        var recentRatings: ArraySlice<Rating> { ratings.suffix(Curriculum.windowSize) }
        var recentPersons: ArraySlice<Int> { persons.suffix(Curriculum.windowSize) }

        /// Share of Good points, nil without answers.
        var share: Double? {
            recentRatings.isEmpty ? nil : recentRatings.map(\.goodPoints).reduce(0, +) / Double(recentRatings.count)
        }
    }

    /// How a unit is doing against the bar.
    struct Progress: Equatable {
        let answers: Int
        let share: Double?
        /// Persons with fewer than two answers in the window.
        let missingPersons: [Int]
        /// Already performed well once and unlocked what comes after it.
        let passed: Bool

        var performsWell: Bool {
            answers >= Curriculum.windowSize && (share ?? 0) >= Curriculum.goodBar && missingPersons.isEmpty
        }

        /// 0…1 for rings and bars: the share against the bar, scaled down while the window is still filling.
        var fraction: Double {
            if passed { return 1 }
            let filled = min(1, Double(answers) / Double(Curriculum.windowSize))
            return min(1, (share ?? 0) / Curriculum.goodBar) * filled
        }
    }

    struct Addition: Equatable {
        let unit: PoolUnit
        /// The unit whose good performance brought it.
        let cause: PoolUnit
    }

    /// In the order they were added. Units are never removed.
    private(set) var units: [PoolUnit]
    private(set) var addedAt: [PoolUnit: Date]
    private(set) var windows: [PoolUnit: Window] = [:]
    private(set) var passed: Set<PoolUnit> = []

    static let startUnits: [PoolUnit] = [.group(.are, .presente), .irregular("essere", .presente)]

    static func initial(at now: Date) -> LearningPool { LearningPool(units: startUnits, at: now) }

    /// Drops units of verbs or tenses that no longer exist; starts over when nothing is left.
    init(units: [PoolUnit], at now: Date) {
        var seen = Set<PoolUnit>()
        let valid = units.filter { $0.isValid && seen.insert($0).inserted }
        self.units = valid.isEmpty ? Self.startUnits : valid
        addedAt = Dictionary(uniqueKeysWithValues: self.units.map { ($0, now) })
    }

    /// Drops a verb's unit in a tense it no longer counts as irregular in (pools saved when irregularity
    /// was decided per verb): there it now belongs to its group, which comes into the pool on its own.
    mutating func dropInvalidUnits() {
        units.removeAll { !$0.isValid }
        if units.isEmpty { units = Self.startUnits }
        addedAt = addedAt.filter { $0.key.isValid }
        windows = windows.filter { $0.key.isValid }
        passed = passed.filter(\.isValid)
    }

    func contains(_ unit: PoolUnit) -> Bool { units.contains(unit) }

    func isFresh(_ unit: PoolUnit, at now: Date) -> Bool {
        addedAt[unit].map { MemoryState.days(from: $0, to: now) < 1 } ?? false
    }

    func progress(of unit: PoolUnit) -> Progress {
        let window = windows[unit] ?? Window()
        let missing = unit.persons.filter { person in window.recentPersons.filter { $0 == person }.count < Curriculum.answersPerPerson }
        return Progress(answers: window.recentRatings.count, share: window.share, missingPersons: missing, passed: passed.contains(unit))
    }

    // MARK: Answers and lessons

    mutating func record(_ key: MemoryKey, _ rating: Rating) {
        windows[key.unit, default: Window()].append(rating, person: key.person)
    }

    /// The same group or irregular verb in earlier tenses that does not perform well right now; while there
    /// is any, the unit unlocks nothing.
    func blockers(of unit: PoolUnit) -> [PoolUnit] {
        let earlier = Curriculum.tenseOrder.prefix { $0 != unit.tense }
        return earlier.compactMap { tense -> PoolUnit? in
            let other: PoolUnit = switch unit {
            case .group(let family, _): .group(family, tense)
            case .irregular(let verb, _): .irregular(verb, tense)
            }
            return contains(other) && !progress(of: other).performsWell ? other : nil
        }
    }

    /// After a lesson: every unit that performs well for the first time, and is not held back by an
    /// earlier tense, unlocks what comes after it.
    mutating func finishLesson(at now: Date) -> [Addition] {
        var additions: [Addition] = []
        for unit in units where !passed.contains(unit) && progress(of: unit).performsWell && blockers(of: unit).isEmpty {
            passed.insert(unit)
            for next in unlocks(of: unit) where !contains(next) {
                add(next, at: now)
                additions.append(Addition(unit: next, cause: unit))
            }
        }
        // An irregular verb that did well waits for its next irregular tense until a regular group has it.
        for unit in units where passed.contains(unit) {
            guard case .irregular(let verb, let tense) = unit, let next = Self.nextIrregularTense(after: tense, for: verb),
                  isOpenForRegular(next), !contains(.irregular(verb, next)), blockers(of: unit).isEmpty else { continue }
            add(.irregular(verb, next), at: now)
            additions.append(Addition(unit: .irregular(verb, next), cause: unit))
        }
        return additions
    }

    /// What a unit brings once it performs well (already present ones included).
    func unlocks(of unit: PoolUnit) -> [PoolUnit] {
        switch unit {
        case .group(let family, let tense):
            var result: [PoolUnit] = []
            if let index = VerbFamily.regular.firstIndex(of: family), index + 1 < VerbFamily.regular.count {
                result.append(.group(VerbFamily.regular[index + 1], tense))
            }
            if let next = Self.nextTense(after: tense) { result.append(.group(family, next)) }
            return result
        case .irregular(let verb, let tense):
            var result: [PoolUnit] = []
            if let next = Curriculum.irregularVerbs(in: tense).first(where: { $0 != verb && !contains(.irregular($0, tense)) }) {
                result.append(.irregular(next, tense))
            }
            if let next = Self.nextIrregularTense(after: tense, for: verb), isOpenForRegular(next) {
                result.append(.irregular(verb, next))
            }
            return result
        }
    }

    private func isOpenForRegular(_ tense: Tense) -> Bool {
        units.contains { if case .group(_, let open) = $0 { open == tense } else { false } }
    }

    static func nextTense(after tense: Tense) -> Tense? {
        Curriculum.tenseOrder.drop { $0 != tense }.dropFirst().first
    }

    /// The next tense in path order that the verb is irregular in; in the others it counts for its group.
    static func nextIrregularTense(after tense: Tense, for verb: String) -> Tense? {
        Curriculum.tenseOrder.drop { $0 != tense }.dropFirst().first(where: VerbLibrary.verb(verb).isIrregular)
    }

    private mutating func add(_ unit: PoolUnit, at now: Date) {
        units.append(unit)
        addedAt[unit] = now
    }
}

/// The fixed parts of the learning path: orders, thresholds and how a lesson is put together.
enum Curriculum {
    static let tenseOrder: [Tense] = [.presente, .passatoprossimo, .imperfetto, .futuro, .imperativo, .condizionale, .congiuntivo]

    /// Regular groups take turns, and the most frequent irregular verbs come early.
    static let verbOrder: [String] = [
        "parlare", "abitare", "essere", "lavorare", "avere", "credere", "fare", "dormire", "andare", "capire",
        "guardare", "stare", "arrivare", "potere", "vendere", "volere", "sentire", "dovere", "finire", "venire",
        "tornare", "dire", "viaggiare", "vedere", "partire", "sapere", "preferire", "prendere", "entrare", "mettere",
        "ricevere", "uscire", "camminare", "leggere", "restare", "scrivere", "seguire", "dare", "pulire", "bere",
        "diventare", "conoscere", "guidare", "chiedere", "temere", "rispondere", "ballare", "aprire", "nuotare", "vivere",
        "mancare", "piacere", "passeggiare", "rimanere", "sembrare", "tenere", "sciare", "decidere", "durare", "scegliere",
        "bastare", "cadere",
        "ripetere", "servire", "spedire", "battere", "vestire", "costruire", "cedere", "fuggire", "obbedire",
        "premere", "bollire", "guarire", "correre", "mentire", "suggerire", "scendere", "offrire", "reagire",
        "perdere", "soffrire", "unire", "vincere", "scoprire", "restituire",
    ]

    /// The verbs irregular in this tense, in path order.
    static func irregularVerbs(in tense: Tense) -> [String] {
        verbOrder.filter { VerbLibrary.verb($0).isIrregular(in: tense) }
    }

    /// A unit performs well with this share of Good points in its last `windowSize` answers …
    static let goodBar = 0.8
    static let windowSize = 20
    /// … and every person answered at least this often among them.
    static let answersPerPerson = 2

    /// Picks `length` questions, favouring what is least known, difficult, freshly added, or in a person ×
    /// tense that lags behind the rest. For a regular group the verb is chosen at random from `verbs`
    /// (different verbs within a lesson where possible). At most 4 questions per unit, unless there are too
    /// few units to fill the lesson.
    static func pickLesson<R: RandomNumberGenerator>(units: [PoolUnit], verbs: (PoolUnit) -> [String], pool: LearningPool,
                                                     memory: LearningMemory, length: Int, at now: Date,
                                                     using rng: inout R) -> [FormKey] {
        let keys = units.flatMap(\.keys)
        guard !keys.isEmpty, length > 0 else { return [] }
        var known: [MemoryKey: Double] = [:]
        for key in keys { known[key] = memory[key]?.retrievability(at: now) ?? 0 }
        let mean = known.values.reduce(0, +) / Double(known.count)
        // A person × tense that lags behind the average is trained more.
        var sums: [PersonTense: (total: Double, count: Int)] = [:]
        for (key, value) in known {
            let sum = sums[PersonTense(key)] ?? (0, 0)
            sums[PersonTense(key)] = (sum.total + value, sum.count + 1)
        }
        let personBoost = sums.mapValues { max(0, mean - $0.total / Double($0.count)) * 1.5 }

        func ranked() -> [MemoryKey] {
            keys.map { key -> (MemoryKey, Double) in
                var need = (1 - known[key]!) * (0.7 + 0.06 * (memory[key]?.difficulty ?? 5))
                need += personBoost[PersonTense(key)] ?? 0
                if pool.isFresh(key.unit, at: now) { need += 0.3 }
                return (key, pow(Double.random(in: 0.001..<1, using: &rng), 1 / max(0.01, need * need)))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        }

        let cap = max(4, (length + units.count - 1) / units.count)
        var perUnit: [PoolUnit: Int] = [:]
        var usedVerbs: Set<String> = []
        var picked: [FormKey] = []
        // A regular pattern may come again (with another verb) when there are too few patterns for the lesson.
        for pass in 0..<4 where picked.count < length {
            for key in ranked() where picked.count < length && perUnit[key.unit, default: 0] < (pass == 0 ? cap : length) {
                let form: FormKey
                switch key {
                case .form(let irregular):
                    guard pass == 0 else { continue }
                    form = irregular
                case .pattern(let pattern):
                    let options = verbs(key.unit).filter {
                        VerbLibrary.verb($0).hasForm(pattern.tense, pattern.person)
                            && !picked.contains(FormKey(verb: $0, tense: pattern.tense, person: pattern.person))
                    }
                    let fresh = options.filter { !usedVerbs.contains($0) }
                    guard let verb = (fresh.isEmpty ? options : fresh).randomElement(using: &rng) else { continue }
                    form = FormKey(verb: verb, tense: pattern.tense, person: pattern.person)
                }
                guard !picked.contains(form) else { continue }
                picked.append(form)
                usedVerbs.insert(form.verb)
                perUnit[key.unit, default: 0] += 1
            }
        }
        return picked
    }
}

private struct PersonTense: Hashable {
    let tense: Tense
    let person: Int

    init(_ key: MemoryKey) {
        tense = key.tense
        person = key.person
    }
}
