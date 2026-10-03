import Foundation

/// One verb in one tense — the unit that is unlocked, practised and levelled.
struct Cell: Hashable, Codable {
    let verb: String
    let tense: Tense
}

struct Unlock: Equatable {
    enum Kind: String, Codable { case verb, tense }

    let cell: Cell
    let kind: Kind
}

/// What the learning path has unlocked so far.
struct CurriculumState: Codable, Equatable {
    /// In the order they were unlocked, newest last. Unlocked cells are never locked again.
    private(set) var unlocked: [Cell]
    /// The verb introduced most recently; only its Presente level decides about the next verb.
    private(set) var frontier: String
    private(set) var lastUnlockKind: Unlock.Kind?

    static let initial = CurriculumState(unlocked: [Cell(verb: Curriculum.verbOrder[0], tense: .presente)],
                                         frontier: Curriculum.verbOrder[0], lastUnlockKind: nil)

    var newest: Cell { unlocked.last! }
    var verbs: Set<String> { Set(unlocked.map(\.verb)) }

    func contains(_ cell: Cell) -> Bool { unlocked.contains(cell) }

    mutating func apply(_ unlock: Unlock) {
        guard !contains(unlock.cell) else { return }
        unlocked.append(unlock.cell)
        lastUnlockKind = unlock.kind
        if unlock.kind == .verb { frontier = unlock.cell.verb }
    }

    /// Unlocks every cell the learner already has a level in, so existing progress carries over.
    /// The latest of those verbs in the path becomes the frontier.
    static func migrated(levels: [String: [String: Int]]) -> CurriculumState {
        let cells = levels.flatMap { verb, tenses in
            tenses.compactMap { raw, level -> Cell? in
                guard level > 0, let tense = Tense(rawValue: raw), let entry = VerbLibrary.all[verb],
                      entry.hasTense(tense) else { return nil }
                return Cell(verb: verb, tense: tense)
            }
        }
        return CurriculumState(sanitizing: cells.sorted { Curriculum.rank($0) < Curriculum.rank($1) })
    }

    /// Drops cells of verbs or tenses that no longer exist; falls back to the initial state when nothing is left.
    init(sanitizing cells: [Cell], frontier: String? = nil, lastUnlockKind: Unlock.Kind? = nil) {
        var seen = Set<Cell>()
        let valid = cells.filter {
            (VerbLibrary.all[$0.verb]?.hasTense($0.tense) ?? false) && seen.insert($0).inserted
        }
        guard !valid.isEmpty else { self = .initial; return }
        unlocked = valid
        let verbs = Set(valid.map(\.verb))
        self.frontier = frontier.flatMap { verbs.contains($0) ? $0 : nil }
            ?? Curriculum.verbOrder.last(where: verbs.contains)!
        self.lastUnlockKind = lastUnlockKind
    }

    private init(unlocked: [Cell], frontier: String, lastUnlockKind: Unlock.Kind?) {
        self.unlocked = unlocked
        self.frontier = frontier
        self.lastUnlockKind = lastUnlockKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sanitizing: try container.decode([Cell].self, forKey: .unlocked),
                  frontier: try container.decodeIfPresent(String.self, forKey: .frontier),
                  lastUnlockKind: try container.decodeIfPresent(Unlock.Kind.self, forKey: .lastUnlockKind))
    }
}

/// The learning path: which verb and tense come next, how a lesson changes a level, and what a lesson contains.
enum Curriculum {
    /// A new verb comes once the frontier verb reaches this level in the Presente.
    static let newVerbLevel = 3
    /// A cell counts as consolidated from this level on, and unlocks the verb's next tense.
    static let consolidatedLevel = 5
    /// At most this many unlocked cells may be below `consolidatedLevel` before anything new is added.
    static let openCap = 4

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

    private static let verbRank = Dictionary(uniqueKeysWithValues: verbOrder.enumerated().map { ($1, $0) })

    /// Sorts cells by verb, then tense, along the path.
    static func rank(_ cell: Cell) -> (Int, Int) {
        (verbRank[cell.verb] ?? Int.max, tenseOrder.firstIndex(of: cell.tense)!)
    }

    // MARK: Levels

    /// How a lesson changes a cell's level, judged on its first answers only.
    static func levelChange(correct: Int, total: Int) -> Int {
        guard total >= 2 else { return 0 }
        let share = Double(correct) / Double(total)
        if share >= 0.8 { return 1 }
        if share < 0.5 { return -1 }
        return 0
    }

    // MARK: Unlocking

    static func openCount(_ state: CurriculumState, level: (Cell) -> Int) -> Int {
        state.unlocked.filter { level($0) < consolidatedLevel }.count
    }

    /// The first verb of the path that has not been introduced yet.
    static func nextVerb(_ state: CurriculumState) -> String? {
        let introduced = state.verbs
        return verbOrder.first { !introduced.contains($0) }
    }

    /// At most one unlock. A new verb needs the frontier at `newVerbLevel` in the Presente; a new tense
    /// needs the verb's previous tense at `consolidatedLevel`. Nothing is added while `openCap` cells are open.
    /// When both are due they take turns.
    static func nextUnlock(_ state: CurriculumState, level: (Cell) -> Int) -> Unlock? {
        guard openCount(state, level: level) < openCap else { return nil }

        var verbUnlock: Unlock?
        if level(Cell(verb: state.frontier, tense: .presente)) >= newVerbLevel, let verb = nextVerb(state) {
            verbUnlock = Unlock(cell: Cell(verb: verb, tense: .presente), kind: .verb)
        }
        let tenseUnlock = verbOrder
            .filter(state.verbs.contains)
            .compactMap { nextTense(of: $0, in: state, level: level) }
            .first
            .map { Unlock(cell: $0, kind: .tense) }

        return state.lastUnlockKind == .verb ? tenseUnlock ?? verbUnlock : verbUnlock ?? tenseUnlock
    }

    /// The verb's first missing tense, if the tense before it is consolidated.
    private static func nextTense(of verb: String, in state: CurriculumState, level: (Cell) -> Int) -> Cell? {
        let tenses = tenseOrder.filter(VerbLibrary.verb(verb).hasTense)
        guard let index = tenses.firstIndex(where: { !state.contains(Cell(verb: verb, tense: $0)) }),
              index > 0, level(Cell(verb: verb, tense: tenses[index - 1])) >= consolidatedLevel else { return nil }
        return Cell(verb: verb, tense: tenses[index])
    }

    // MARK: Lessons

    /// A learning-path lesson: a few cells with several persons each, so every cell gets enough answers
    /// to be judged. The newest cell is always there and at least half the cells are still open.
    /// Fewer than `length` items only when the unlocked cells have fewer forms than that.
    static func composeLesson(_ state: CurriculumState, length: Int, level: (Cell) -> Int) -> [ConjugationItem] {
        let newest = state.newest
        var chosen = [newest]
        let target = min((length + 3) / 4, state.unlocked.count)
        let open = state.unlocked.filter { $0 != newest && level($0) < consolidatedLevel }
        chosen += weightedSample(open, count: max(0, (target + 1) / 2 - chosen.count), level: level)
        var rest = state.unlocked.filter { !chosen.contains($0) }
        chosen += weightedSample(rest, count: target - chosen.count, level: level)

        // Add cells while the chosen ones have too few forms to fill the lesson.
        rest = weightedSample(state.unlocked.filter { !chosen.contains($0) }, count: .max, level: level)
        while chosen.map(persons).map(\.count).reduce(0, +) < length, !rest.isEmpty {
            chosen.append(rest.removeFirst())
        }

        // Deal persons round-robin so the cells share the lesson evenly.
        var decks = chosen.map { persons($0).shuffled() }
        var items: [ConjugationItem] = []
        while items.count < length, decks.contains(where: { !$0.isEmpty }) {
            for index in decks.indices where items.count < length && !decks[index].isEmpty {
                let cell = chosen[index]
                items.append(ConjugationItem(verb: cell.verb, tense: cell.tense, person: decks[index].removeFirst()))
            }
        }
        return items
    }

    private static func persons(_ cell: Cell) -> [Int] {
        cell.tense.persons.filter { VerbLibrary.verb(cell.verb).hasForm(cell.tense, $0) }
    }

    /// Weighted sampling without replacement: level 0 is five times as likely as a mastered level.
    static func weightedSample<T>(_ items: [T], count: Int, level: (T) -> Int) -> [T] {
        guard count > 0 else { return [] }
        let scored = items.map { item -> (T, Double) in
            let weight = 1 + Double(ProgressStore.maxLevel - level(item)) * 0.4
            return (item, pow(Double.random(in: 0..<1), 1 / weight))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(count).map(\.0)
    }
}
