import Foundation
import Observation

enum LessonLength: Codable, Hashable, Identifiable {
    case count(Int)
    case all

    var id: String { label }

    var label: String {
        switch self {
        case .count(let n): "\(n)"
        case .all: "Alle Kombinationen"
        }
    }

    func resolve(poolSize: Int) -> Int {
        switch self {
        case .count(let n): min(n, poolSize)
        case .all: poolSize
        }
    }
}

enum ConjugationMode: String, Codable, CaseIterable, Identifiable {
    /// The learning path picks the verbs and tenses.
    case path
    /// The learner picks from what the path has unlocked.
    case free

    var id: String { rawValue }

    var label: String {
        switch self {
        case .path: "Lernpfad"
        case .free: "Freies Üben"
        }
    }
}

/// What round 1 of a conjugation lesson changed.
struct LessonOutcome {
    /// A verb×tense's stability in days before and after the lesson; `from` is nil for one answered the first time.
    struct StabilityChange: Identifiable {
        let cell: Cell
        let from: Double?
        let to: Double
        var id: Cell { cell }
    }

    let changes: [StabilityChange]
    let addition: LearningPool.Addition?
}

/// Everything that survives app restarts: exercise settings, what the learner remembers, the learning pool
/// and the answer history.
@Observable
final class ProgressStore {
    static let maxLevel = 10

    struct ConjugationSettings: Codable {
        var mode: ConjugationMode = .path
        /// The selection for free practice, kept within what the learning path has unlocked.
        var verbs: Set<String> = [Curriculum.verbOrder[0]]
        var tenses: Set<Tense> = [.presente]
        var length: LessonLength = .count(5)
    }

    struct AuxSettings: Codable {
        var verbs: Set<String> = Set(VerbLibrary.orderedKeys)
        var length: LessonLength = .count(10)
    }

    var conjugation: ConjugationSettings { didSet { save(conjugation, key: Keys.settings) } }
    var aux: AuxSettings { didSet { save(aux, key: Keys.auxSettings) } }
    /// Difficulty, stability and retrievability per form, verb×tense and group pattern. Updated after every first answer.
    private(set) var memory: LearningMemory { didSet { save(memory, key: Keys.memory) } }
    /// The verbs and tenses in play.
    private(set) var pool: LearningPool { didSet { save(pool, key: Keys.pool) } }
    /// "verb|tense" pairs answered wrong in round 1 of the most recently started lesson (shown in red).
    private(set) var lastMistakes: Set<String> { didSet { save(lastMistakes, key: Keys.lastMistakes) } }
    /// Separate mastery for essere/avere — it measures a different skill. Only first attempts count.
    private(set) var auxLevels: [String: Int] { didSet { save(auxLevels, key: Keys.auxLevels) } }

    /// Every first answer, aggregated per day for the statistics.
    let history: AnswerHistory
    /// Every first answer with its effect on memory, for the verb details.
    let log: AnswerLog
    /// The clock for everything time-based; tests replace it.
    let now: () -> Date

    private let defaults: UserDefaults

    private enum Keys {
        static let settings = "coniugazione-settings"
        static let memory = "coniugazione-dsr-memory"
        static let pool = "coniugazione-pool"
        static let lastMistakes = "coniugazione-tense-mistakes"
        // Earlier schemes, newest first: a half-life per verb×tense, per-lesson levels per verb×tense, and the
        // unlocked verb×tense of the first learning path.
        static let halfLives = "coniugazione-memory"
        static let tenseLevels = "coniugazione-tense-levels"
        static let curriculum = "coniugazione-curriculum"
        // Per-verb data from before mastery was tracked per tense.
        static let legacyLevels = "coniugazione-levels"
        static let legacyLastMistakes = "coniugazione-last-mistakes"
        static let auxSettings = "coniugazione-aux-settings"
        static let auxLevels = "coniugazione-aux-levels"
    }

    init(defaults: UserDefaults = .standard, historyURL: URL? = AnswerHistory.defaultURL,
         logURL: URL? = AnswerLog.defaultURL, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        history = AnswerHistory(fileURL: historyURL)
        log = AnswerLog(fileURL: logURL)
        var conjugation = Self.load(ConjugationSettings.self, key: Keys.settings, from: defaults) ?? ConjugationSettings()
        conjugation.verbs.formIntersection(VerbLibrary.orderedKeys)
        if conjugation.verbs.isEmpty { conjugation.verbs = ConjugationSettings().verbs }
        if conjugation.tenses.isEmpty { conjugation.tenses = [.presente] }
        self.conjugation = conjugation

        var aux = Self.load(AuxSettings.self, key: Keys.auxSettings, from: defaults) ?? AuxSettings()
        aux.verbs.formIntersection(VerbLibrary.orderedKeys)
        if aux.verbs.isEmpty { aux.verbs = Set(VerbLibrary.orderedKeys) }
        self.aux = aux

        lastMistakes = Self.load(Set<String>.self, key: Keys.lastMistakes, from: defaults) ?? []
        auxLevels = Self.load([String: Int].self, key: Keys.auxLevels, from: defaults) ?? [:]
        let start = now()
        let storedMemory = Self.load(LearningMemory.self, key: Keys.memory, from: defaults)
        let memory = storedMemory ?? Self.migratedMemory(from: defaults, at: start)
        self.memory = memory
        let storedPool = Self.load(LearningPool.self, key: Keys.pool, from: defaults)
        pool = storedPool ?? Self.migratedPool(from: defaults, memory: memory, at: start)
        keepFreeSelectionUnlocked()

        if storedMemory == nil { save(memory, key: Keys.memory) }
        if storedPool == nil { save(pool, key: Keys.pool) }
        for key in [Keys.halfLives, Keys.tenseLevels, Keys.curriculum, Keys.legacyLevels, Keys.legacyLastMistakes] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Migration

    private struct OldHalfLife: Decodable {
        let halfLife: Double
        let last: Date
    }

    private struct OldCurriculum: Decodable {
        let unlocked: [Cell]
    }

    /// Earlier progress becomes verb×tense memory: a half-life is a stability, a per-lesson level a stability
    /// on the same scale; the per-verb levels before that count as Presente.
    private static func migratedMemory(from defaults: UserDefaults, at now: Date) -> LearningMemory {
        var memory = LearningMemory()
        func set(_ verb: String, _ raw: String, stability: Double, last: Date) {
            guard let tense = Tense(rawValue: raw), VerbLibrary.all[verb]?.hasTense(tense) == true else { return }
            memory.cells[Cell(verb: verb, tense: tense)] = MemoryState(
                difficulty: 5, stability: stability, retrievability: 0.9, last: last, lastRating: .good, answers: 0, good: 0)
        }
        if let halfLives = load([String: [String: OldHalfLife]].self, key: Keys.halfLives, from: defaults) {
            for (verb, tenses) in halfLives { for (raw, old) in tenses { set(verb, raw, stability: old.halfLife, last: old.last) } }
            return memory
        }
        let levels = load([String: [String: Int]].self, key: Keys.tenseLevels, from: defaults)
            ?? (load([String: Int].self, key: Keys.legacyLevels, from: defaults) ?? [:]).mapValues { [Tense.presente.rawValue: $0] }
        for (verb, tenses) in levels {
            for (raw, level) in tenses where level > 0 { set(verb, raw, stability: 0.5 * pow(2, 0.32 * Double(level)), last: now) }
        }
        return memory
    }

    /// The start cells plus whatever was unlocked or practised before.
    private static func migratedPool(from defaults: UserDefaults, memory: LearningMemory, at now: Date) -> LearningPool {
        let unlocked = load(OldCurriculum.self, key: Keys.curriculum, from: defaults)?.unlocked ?? []
        let practised = memory.cells.keys.sorted { Curriculum.rank($0) < Curriculum.rank($1) }
        return LearningPool(cells: LearningPool.startCells + unlocked + practised, at: now)
    }

    // MARK: Conjugation

    func state(of cell: Cell) -> MemoryState? { memory.cells[cell] }
    func state(of form: FormKey) -> MemoryState? { memory.forms[form] }
    func patternState(of form: FormKey) -> MemoryState? { PatternKey(form).flatMap { memory.patterns[$0] } }

    /// Stability of a verb×tense in days; 0 for one never answered.
    func stability(of cell: Cell) -> Double { state(of: cell)?.stability ?? 0 }

    /// Chance of recalling it right now, 0…1.
    func retrievability(of cell: Cell) -> Double { state(of: cell)?.retrievability(at: now()) ?? 0 }

    /// The ring: 0…10 on a log scale of the verb×tense stability (a full ring is about three months), so it
    /// shows strength and does not sink by the day.
    func level(of verb: String, tense: Tense) -> Int {
        state(of: Cell(verb: verb, tense: tense)).map { Self.level(stability: $0.stability) } ?? 0
    }

    static func level(stability: Double) -> Int {
        min(maxLevel, max(0, Int(log2(stability / 0.5) / 0.75)))
    }

    /// The level in every tense the verb has forms in.
    func levels(of verb: String) -> [Tense: Int] {
        Dictionary(uniqueKeysWithValues: Tense.allCases.filter(VerbLibrary.verb(verb).hasTense).map {
            ($0, level(of: verb, tense: $0))
        })
    }

    /// What a verb chip's ring shows: the average over the given tenses, rounded down.
    /// Tenses the verb has no forms in (potere has no imperative) are left out.
    func level(of verb: String, tenses: Set<Tense>) -> Int {
        let relevant = tenses.filter { VerbLibrary.verb(verb).hasTense($0) }
        guard !relevant.isEmpty else { return 0 }
        return relevant.map { level(of: verb, tense: $0) }.reduce(0, +) / relevant.count
    }

    func isRecentMistake(verb: String, tenses: Set<Tense>) -> Bool {
        tenses.contains { lastMistakes.contains(Self.mistakeKey(verb, $0)) }
    }

    /// Records a first answer on all three memory levels and in the pool's fast-track streaks, and for the
    /// statistics, the verb log and the red markers.
    func record(_ item: ConjugationItem, _ rating: Rating) {
        let time = now()
        let form = FormKey(verb: item.verb, tense: item.tense, person: item.person)
        let before = memory.forms[form]
        memory.record(form, rating, at: time)
        pool.record(form, rating)
        log.append(AnswerLogEntry(date: time, verb: item.verb, tense: item.tense, person: item.person, gender: item.gender,
                                  rating: rating, retrievabilityBefore: before?.retrievability(at: time) ?? 0,
                                  stabilityBefore: before?.stability, stabilityAfter: memory.forms[form]!.stability))
        if rating == .again { lastMistakes.insert(Self.mistakeKey(item.verb, item.tense)) }
        history.record(verb: item.verb, tense: item.tense, correct: rating != .again, on: time)
    }

    func resetLastMistakes() { lastMistakes = [] }

    /// Ends round 1: reports how the practised verb×tense moved since `before` (stabilities when the lesson
    /// started) and lets the pool grow by at most one verb×tense.
    func finishLesson(ratings: [Rating], practised: Set<Cell>, before: [Cell: Double]) -> LessonOutcome {
        let changes = practised.sorted { Curriculum.rank($0) < Curriculum.rank($1) }.compactMap { cell -> LessonOutcome.StabilityChange? in
            state(of: cell).map { .init(cell: cell, from: before[cell], to: $0.stability) }
        }
        return LessonOutcome(changes: changes, addition: pool.finishLesson(ratings: ratings, memory: memory, at: now()))
    }

    /// What comes next and how close it is.
    var readiness: LearningPool.Readiness? { pool.readiness(memory: memory, at: now()) }

    /// A lesson from the pool (learning path) or from the given forms (free practice).
    func pickLesson(length: Int, from candidates: [FormKey]? = nil) -> [FormKey] {
        var rng = SystemRandomNumberGenerator()
        return Curriculum.pickLesson(from: candidates ?? pool.cells.flatMap(Curriculum.forms), pool: pool, memory: memory,
                                     length: length, at: now(), using: &rng)
    }

    // MARK: Learning path

    func isUnlocked(verb: String, tense: Tense) -> Bool { pool.contains(Cell(verb: verb, tense: tense)) }

    /// Verbs in the pool, in path order.
    var unlockedVerbs: [String] { Curriculum.verbOrder.filter(pool.verbs.contains) }

    /// A verb's unlocked tenses in path order.
    func unlockedTenses(of verb: String) -> [Tense] {
        Curriculum.tenseOrder.filter { isUnlocked(verb: verb, tense: $0) }
    }

    /// Tenses unlocked for at least one verb, in path order.
    var unlockedTenses: [Tense] {
        let tenses = Set(pool.cells.map(\.tense))
        return Curriculum.tenseOrder.filter(tenses.contains)
    }

    /// Free practice may only offer what the path has unlocked.
    private func keepFreeSelectionUnlocked() {
        var settings = conjugation
        settings.verbs.formIntersection(pool.verbs)
        if settings.verbs.isEmpty { settings.verbs = [pool.cells[0].verb] }
        settings.tenses.formIntersection(unlockedTenses)
        if settings.tenses.isEmpty { settings.tenses = [.presente] }
        if settings.verbs != conjugation.verbs || settings.tenses != conjugation.tenses { conjugation = settings }
    }

    // MARK: Essere o avere

    func auxLevel(of verb: String) -> Int { auxLevels[verb] ?? 0 }

    func recordAuxAnswer(verb: String, correct: Bool) {
        auxLevels[verb] = Self.step(auxLevel(of: verb), correct: correct)
    }

    // MARK: Reset

    /// Clears memory and levels (both exercises), the learning pool, the recent mistakes, the statistics and
    /// the answer log. The other settings are kept; free practice falls back to what is in the pool.
    func resetProgress() {
        memory = LearningMemory()
        log.reset()
        pool = .initial(at: now())
        keepFreeSelectionUnlocked()
        lastMistakes = []
        auxLevels = [:]
        history.reset()
    }

    // MARK: Helpers

    private static func mistakeKey(_ verb: String, _ tense: Tense) -> String { "\(verb)|\(tense.rawValue)" }

    private static func step(_ level: Int, correct: Bool) -> Int {
        correct ? min(maxLevel, level + 1) : max(0, level - 1)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension ProgressStore.ConjugationSettings {
    /// Settings saved before a field existed still load, with that field's default.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ConjugationMode.self, forKey: .mode) ?? mode
        verbs = try container.decodeIfPresent(Set<String>.self, forKey: .verbs) ?? verbs
        tenses = try container.decodeIfPresent(Set<Tense>.self, forKey: .tenses) ?? tenses
        length = try container.decodeIfPresent(LessonLength.self, forKey: .length) ?? length
    }
}

extension Set {
    /// Toggles membership but never removes the last element.
    mutating func toggleKeepingOne(_ element: Element) {
        if contains(element) {
            if count > 1 { remove(element) }
        } else {
            insert(element)
        }
    }
}
