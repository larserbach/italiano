import Foundation

/// What the learner is working on: whole regular groups and single irregular verbs, each in a tense. Whether a
/// verb is irregular is decided per tense: scrivere counts for -ere in the Presente and on its own in the
/// Passato prossimo.
///
/// It starts with all -are verbs and essere in the Presente. A unit that performs well (every person answered
/// at least twice, and ≥ 80 % Good in the last 4 answers of each person, a looked-up answer counting half)
/// unlocks:
/// a regular group itself in the next tense and, in the Presente only, the next group; an irregular verb the
/// next verb that is first irregular in the same tense, and itself in the next tense it is irregular in once a
/// regular group has that tense. So a verb always starts in its first irregular tense: venire comes in the
/// Presente and reaches the Passato prossimo through itself, never through another verb's Passato prossimo.
/// A unit in a later tense only unlocks while the same group or verb is still at ≥ 80 % Good in every earlier
/// tense in the pool; whether every person is still in that tense's window does not matter there.
/// A group in a later tense only asks about verbs already met in the Presente (`verbs(of:)`).
struct LearningPool: Codable, Equatable {
    /// The last answers of a unit, with the person each was about: the last `answersKeptPerPerson` of each
    /// person, so a person only loses an answer by being asked again and can't drift out behind the others.
    struct Window: Codable, Equatable {
        private(set) var ratings: [Rating] = []
        private(set) var persons: [Int] = []

        init() {}

        /// A window saved as the last 20 answers of the unit keeps what it holds of each person.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ratings = try container.decode([Rating].self, forKey: .ratings)
            persons = try container.decode([Int].self, forKey: .persons)
            trim()
        }

        mutating func append(_ rating: Rating, person: Int) {
            ratings.append(rating)
            persons.append(person)
            trim()
        }

        /// Drops each person's answers beyond their last `answersKeptPerPerson`.
        private mutating func trim() {
            var kept: [Int: Int] = [:]
            let keep = persons.indices.reversed().filter { index in
                kept[persons[index], default: 0] += 1
                return kept[persons[index]]! <= Curriculum.answersKeptPerPerson
            }.reversed()
            guard keep.count < persons.count else { return }
            ratings = keep.map { ratings[$0] }
            persons = keep.map { persons[$0] }
        }

        func count(of person: Int) -> Int { persons.filter { $0 == person }.count }

        /// Share of Good points, nil without answers.
        var share: Double? {
            ratings.isEmpty ? nil : ratings.map(\.goodPoints).reduce(0, +) / Double(ratings.count)
        }
    }

    /// How a unit is doing against the bar.
    struct Progress: Equatable {
        /// All answers kept, up to `answersKeptPerPerson` per person.
        let answers: Int
        /// Answers toward `needed`: up to `answersPerPerson` per person.
        let counted: Int
        /// `answersPerPerson` for each of the unit's persons.
        let needed: Int
        let share: Double?
        /// Persons with fewer than `answersPerPerson` answers.
        let missingPersons: [Int]
        /// Already performed well once and unlocked what comes after it.
        let passed: Bool

        var performsWell: Bool {
            missingPersons.isEmpty && (share ?? 0) >= Curriculum.goodBar
        }

        /// 0…1 for rings and bars: the share against the bar, scaled down while persons still lack answers.
        var fraction: Double {
            if passed { return 1 }
            let filled = needed == 0 ? 1 : Double(counted) / Double(needed)
            return min(1, (share ?? 0) / Curriculum.goodBar) * filled
        }
    }

    struct Addition: Equatable {
        let unit: PoolUnit
        /// The unit whose good performance brought it.
        let cause: PoolUnit
    }

    /// In the order they were added. Units stay, unless a catalog change makes them invalid (`dropInvalidUnits`).
    private(set) var units: [PoolUnit]
    private(set) var addedAt: [PoolUnit: Date]
    private(set) var windows: [PoolUnit: Window] = [:]
    /// Units that performed well once and unlocked what comes after them. They stay passed if they slip later.
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

    /// Whether the verb is in the pool in the Presente, in its group or on its own.
    func hasMet(_ verb: String) -> Bool { contains(PoolUnit(verb: verb, tense: .presente)) }

    /// The verbs a unit asks about now. A group in a later tense leaves out verbs not met in the Presente
    /// yet, so venivo waits for venire · Presente.
    func verbs(of unit: PoolUnit) -> [String] { unit.verbs.filter(hasMet) }

    func progress(of unit: PoolUnit) -> Progress {
        let window = windows[unit] ?? Window()
        let counts = unit.persons.map { min(window.count(of: $0), Curriculum.answersPerPerson) }
        let missing = zip(unit.persons, counts).filter { $0.1 < Curriculum.answersPerPerson }.map(\.0)
        return Progress(answers: window.ratings.count, counted: counts.reduce(0, +),
                        needed: unit.persons.count * Curriculum.answersPerPerson, share: window.share,
                        missingPersons: missing, passed: passed.contains(unit))
    }

    // MARK: Answers and lessons

    mutating func record(_ key: MemoryKey, _ rating: Rating) {
        windows[key.unit, default: Window()].append(rating, person: key.person)
    }

    /// The same group or irregular verb in earlier tenses whose share of Good is below the bar right now;
    /// while there is any, the unit unlocks nothing. Only the share counts: every person was answered
    /// enough there when it passed, and a well-known person drifting out of its window does not hold back.
    func blockers(of unit: PoolUnit) -> [PoolUnit] {
        let earlier = Curriculum.tenseOrder.prefix { $0 != unit.tense }
        return earlier.compactMap { tense -> PoolUnit? in
            let other: PoolUnit = switch unit {
            case .group(let family, _): .group(family, tense)
            case .irregular(let verb, _): .irregular(verb, tense)
            }
            return contains(other) && (progress(of: other).share ?? 0) < Curriculum.goodBar ? other : nil
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
            // The next group only comes in the Presente; later tenses open per group, from its own earlier tense.
            if tense == .presente, let index = VerbFamily.regular.firstIndex(of: family), index + 1 < VerbFamily.regular.count {
                result.append(.group(VerbFamily.regular[index + 1], tense))
            }
            if let next = Self.nextTense(after: tense) { result.append(.group(family, next)) }
            return result
        case .irregular(let verb, let tense):
            var result: [PoolUnit] = []
            if let next = Curriculum.irregularVerbs(in: tense).first(where: {
                $0 != verb && !contains(.irregular($0, tense)) && Self.firstIrregularTense(of: $0) == tense
            }) {
                result.append(.irregular(next, tense))
            }
            if let next = Self.nextIrregularTense(after: tense, for: verb), isOpenForRegular(next) {
                result.append(.irregular(verb, next))
            }
            return result
        }
    }

    /// Whether some regular group is in this tense yet. An irregular verb's later tense waits for that,
    /// so tenses still open in path order.
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

    /// The tense in path order a verb starts in.
    static func firstIrregularTense(of verb: String) -> Tense? {
        Curriculum.tenseOrder.first(where: VerbLibrary.verb(verb).isIrregular)
    }

    private mutating func add(_ unit: PoolUnit, at now: Date) {
        units.append(unit)
        addedAt[unit] = now
    }
}
