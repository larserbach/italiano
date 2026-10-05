import Foundation

/// What the learner is working on: the verb×tense cells in play, and what comes next.
///
/// New cells are added after lessons that went well: the last two lessons ≥ 90 % Good (a looked-up answer
/// counts half) and nearly the whole pool well retrieved. In every open tense each verb family comes first,
/// with new families and irregular verbs needing less; then new Presente vocabulary and more verbs in the
/// newest tense take turns. The next tense opens once the newest one has 5 verbs and the Presente 10 per
/// open tense. A regular family whose last 6 answers in a tense were all Good, across 4 persons, gets new
/// verbs of that tense at once (fast track).
struct LearningPool: Codable, Equatable {
    struct FamilyTense: Hashable, Codable {
        let family: VerbFamily
        let tense: Tense
    }

    /// An unbroken run of Good answers and the persons it covered.
    struct Streak: Codable, Equatable {
        var count = 0
        var persons: Set<Int> = []

        var grantsFastTrack: Bool { count >= Curriculum.fastTrackAnswers && persons.count >= Curriculum.fastTrackPersons }
    }

    struct Addition: Equatable {
        enum Reason: Equatable { case ready, fastTrack }

        let cell: Cell
        let reason: Reason
    }

    /// What decides the next addition, for the decision itself and for showing it.
    struct Readiness: Equatable {
        let next: Cell
        /// A new family in that tense or an irregular verb: the pool needs to be a little less settled.
        let eager: Bool
        let fastTrack: Bool
        /// Share of Good points in the rated lessons, nil before any lesson.
        let goodShare: Double?
        let settledCells: Int
        let settledNeeded: Int

        var lessonsOK: Bool { (goodShare ?? 0) >= Curriculum.goodBar }
        var poolOK: Bool { settledCells >= settledNeeded }
    }

    /// In the order they were added. Cells are never removed.
    private(set) var cells: [Cell]
    private(set) var addedAt: [Cell: Date]
    /// First-attempt ratings of the last lesson; readiness looks at the last two lessons.
    private(set) var previousRatings: [Rating] = []
    private(set) var streaks: [FamilyTense: Streak] = [:]
    /// Alternates between new Presente vocabulary and more verbs in the newest tense.
    private(set) var deepenNext = false

    /// Starts with the first -are verb, both auxiliaries and an -ire verb.
    static let startCells = ["parlare", "avere", "essere", "dormire"].map { Cell(verb: $0, tense: .presente) }

    static func initial(at now: Date) -> LearningPool { LearningPool(cells: startCells, at: now) }

    /// Drops cells of verbs or tenses that no longer exist; starts over when nothing is left.
    init(cells: [Cell], at now: Date) {
        var seen = Set<Cell>()
        let valid = cells.filter { (VerbLibrary.all[$0.verb]?.hasTense($0.tense) ?? false) && seen.insert($0).inserted }
        self.cells = valid.isEmpty ? Self.startCells : valid
        addedAt = Dictionary(uniqueKeysWithValues: self.cells.map { ($0, now) })
    }

    var verbs: Set<String> { Set(cells.map(\.verb)) }

    func contains(_ cell: Cell) -> Bool { cells.contains(cell) }

    func verbs(in tense: Tense) -> [String] { cells.filter { $0.tense == tense }.map(\.verb) }

    var openTenses: [Tense] { Curriculum.tenseOrder.filter { tense in cells.contains { $0.tense == tense } } }

    func isFresh(_ cell: Cell, at now: Date) -> Bool {
        addedAt[cell].map { MemoryState.days(from: $0, to: now) < 1 } ?? false
    }

    // MARK: Answers and lessons

    mutating func record(_ form: FormKey, _ rating: Rating) {
        let family = VerbFamily(verb: form.verb)
        guard family != .irregular else { return }
        let key = FamilyTense(family: family, tense: form.tense)
        switch rating {
        case .good:
            streaks[key, default: Streak()].count += 1
            streaks[key, default: Streak()].persons.insert(form.person)
        case .again:
            streaks[key] = nil
        case .correct:
            break
        }
    }

    /// Adds at most one cell after a lesson, judged on its first-attempt ratings and the one before.
    mutating func finishLesson(ratings: [Rating], memory: LearningMemory, at now: Date) -> Addition? {
        guard !ratings.isEmpty else { return nil }
        let readiness = readiness(lessonRatings: ratings, memory: memory, at: now)
        previousRatings = ratings
        guard let readiness else { return nil }
        let reason: Addition.Reason
        if readiness.fastTrack {
            reason = .fastTrack
        } else if readiness.lessonsOK && readiness.poolOK {
            reason = .ready
        } else {
            return nil
        }
        add(readiness.next, at: now)
        return Addition(cell: readiness.next, reason: reason)
    }

    /// The next cell and how close it is. Without `lessonRatings` it shows the state before the next lesson.
    func readiness(lessonRatings: [Rating] = [], memory: LearningMemory, at now: Date) -> Readiness? {
        guard let next = nextCell() else { return nil }
        let family = VerbFamily(verb: next.verb)
        let eager = family == .irregular || !verbs(in: next.tense).map(VerbFamily.init).contains(family)
        let recent = previousRatings + lessonRatings
        let settled = cells.filter {
            guard let state = memory.cells[$0] else { return false }
            return state.retrievability(at: now) >= (eager ? 0.7 : 0.8) && state.lastRating == .good
        }
        let share = Double(cells.count) * (eager ? 0.8 : 0.9)
        return Readiness(
            next: next, eager: eager,
            fastTrack: family != .irregular && (streaks[FamilyTense(family: family, tense: next.tense)]?.grantsFastTrack ?? false),
            goodShare: recent.isEmpty ? nil : recent.map(\.goodPoints).reduce(0, +) / Double(recent.count),
            settledCells: settled.count, settledNeeded: Int(share.rounded(.up)))
    }

    private mutating func add(_ cell: Cell, at now: Date) {
        cells.append(cell)
        addedAt[cell] = now
        // The next addition is judged on fresh lessons only.
        previousRatings = []
        deepenNext = cell.tense == .presente
    }

    // MARK: What comes next

    /// The next cell: cover every family in each open tense first; open the next tense once the newest one
    /// has enough verbs and the Presente enough vocabulary; otherwise alternate between new Presente verbs
    /// and more verbs in the newest tense, irregular and regular verbs taking turns.
    func nextCell() -> Cell? {
        for tense in openTenses {
            let present = Set(verbs(in: tense).map(VerbFamily.init))
            for family in VerbFamily.allCases where !present.contains(family) {
                if let verb = candidates(tense, family).first { return Cell(verb: verb, tense: tense) }
            }
        }
        let latest = openTenses.last ?? .presente
        let latestIndex = Curriculum.tenseOrder.firstIndex(of: latest)!
        if verbs(in: latest).count >= Curriculum.nextTenseVerbs,
           verbs(in: .presente).count >= Curriculum.presenteVerbsPerTense * openTenses.count,
           latestIndex + 1 < Curriculum.tenseOrder.count {
            let next = Curriculum.tenseOrder[latestIndex + 1]
            if let verb = candidates(next, nil).first { return Cell(verb: verb, tense: next) }
        }
        let tense = deepenNext && latest != .presente ? latest : .presente
        let lastWasIrregular = cells.last.map { VerbFamily(verb: $0.verb) == .irregular } ?? false
        let options = candidates(tense, nil)
        let preferred = options.first { (VerbFamily(verb: $0) == .irregular) != lastWasIrregular }
        if let verb = preferred ?? options.first { return Cell(verb: verb, tense: tense) }
        return candidates(latest, nil).first.map { Cell(verb: $0, tense: latest) }
    }

    /// Verbs that could join `tense`, in path order. Beyond the Presente only verbs already in the pool,
    /// and only once they have the tense before (the one before that the verb has, for potere & co.).
    private func candidates(_ tense: Tense, _ family: VerbFamily?) -> [String] {
        let source = tense == .presente ? Curriculum.verbOrder : Curriculum.verbOrder.filter(verbs.contains)
        return source.filter { verb in
            let entry = VerbLibrary.verb(verb)
            guard entry.hasTense(tense), !contains(Cell(verb: verb, tense: tense)),
                  family == nil || VerbFamily(verb: verb) == family else { return false }
            guard tense != .presente else { return true }
            let earlier = Curriculum.tenseOrder.prefix { $0 != tense }.filter(entry.hasTense)
            return earlier.last.map { contains(Cell(verb: verb, tense: $0)) } ?? true
        }
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
    ]

    /// Share of Good points in the last two lessons needed for a new cell.
    static let goodBar = 0.9
    /// The next tense opens once the newest tense has this many verbs …
    static let nextTenseVerbs = 5
    /// … and the Presente this many verbs per open tense.
    static let presenteVerbsPerTense = 10
    /// Fast track for a regular family in a tense: this many Good answers in a row, over this many persons.
    static let fastTrackAnswers = 6
    static let fastTrackPersons = 4

    private static let verbRank = Dictionary(uniqueKeysWithValues: verbOrder.enumerated().map { ($1, $0) })

    /// Sorts cells by verb, then tense, along the path.
    static func rank(_ cell: Cell) -> (Int, Int) {
        (verbRank[cell.verb] ?? Int.max, tenseOrder.firstIndex(of: cell.tense)!)
    }

    static func forms(_ cell: Cell) -> [FormKey] {
        cell.tense.persons.filter { VerbLibrary.verb(cell.verb).hasForm(cell.tense, $0) }
            .map { FormKey(verb: cell.verb, tense: cell.tense, person: $0) }
    }

    /// Picks `length` forms, favouring what is least known (all three memory levels), difficult, freshly
    /// added, or in a person × tense that lags behind the rest. At most 4 per verb×tense, unless there are
    /// too few verb×tense to fill the lesson.
    static func pickLesson<R: RandomNumberGenerator>(from candidates: [FormKey], pool: LearningPool, memory: LearningMemory,
                                                     length: Int, at now: Date, using rng: inout R) -> [FormKey] {
        guard !candidates.isEmpty else { return [] }
        var known: [FormKey: Double] = [:]
        for form in candidates { known[form] = memory.known(form, at: now) }
        let mean = known.values.reduce(0, +) / Double(known.count)
        // A person × tense that lags behind the average is trained more.
        var sums: [PersonTense: (total: Double, count: Int)] = [:]
        for (form, value) in known {
            let key = PersonTense(form)
            let sum = sums[key] ?? (0, 0)
            sums[key] = (sum.total + value, sum.count + 1)
        }
        let personBoost = sums.mapValues { max(0, mean - $0.total / Double($0.count)) * 1.5 }

        let scored = known.keys.map { form -> (FormKey, Double) in
            var need = (1 - known[form]!) * (0.7 + 0.06 * (memory.forms[form]?.difficulty ?? 5))
            need += personBoost[PersonTense(form)] ?? 0
            if pool.isFresh(form.cell, at: now) { need += 0.3 }
            return (form, pow(Double.random(in: 0.001..<1, using: &rng), 1 / max(0.01, need * need)))
        }
        let cellCount = Set(candidates.map(\.cell)).count
        let cap = max(4, (length + cellCount - 1) / cellCount)
        var perCell: [Cell: Int] = [:]
        var picked: [FormKey] = []
        for (form, _) in scored.sorted(by: { $0.1 > $1.1 }) where picked.count < length && perCell[form.cell, default: 0] < cap {
            picked.append(form)
            perCell[form.cell, default: 0] += 1
        }
        return picked
    }
}

private struct PersonTense: Hashable {
    let tense: Tense
    let person: Int

    init(_ form: FormKey) {
        tense = form.tense
        person = form.person
    }
}
