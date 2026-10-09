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
    /// A unit's share of Good points in its last answers, before and after the lesson.
    struct ProgressChange: Identifiable {
        let unit: PoolUnit
        let from: Double?
        let to: Double?
        var id: PoolUnit { unit }
    }

    let changes: [ProgressChange]
    let additions: [LearningPool.Addition]
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
    /// Difficulty, stability and retrievability per group pattern and irregular form. Updated after every first answer.
    private(set) var memory: LearningMemory { didSet { save(memory, key: Keys.memory) } }
    /// The groups and irregular verbs in play, per tense.
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
        static let memory = "coniugazione-group-memory"
        static let pool = "coniugazione-group-pool"
        static let lastMistakes = "coniugazione-tense-mistakes"
        // Earlier schemes, newest first: verb×tense cells with memory per verb, a half-life per verb×tense,
        // per-lesson levels per verb×tense, and the unlocked verb×tense of the first learning path.
        static let cellPool = "coniugazione-pool"
        static let cellMemory = "coniugazione-dsr-memory"
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
        memory = Self.load(LearningMemory.self, key: Keys.memory, from: defaults) ?? LearningMemory()
        let storedPool = Self.load(LearningPool.self, key: Keys.pool, from: defaults)
        var pool = storedPool ?? Self.migratedPool(from: defaults, at: start)
        pool.dropInvalidUnits()
        self.pool = pool
        keepFreeSelectionUnlocked()

        if storedPool != pool { save(pool, key: Keys.pool) }
        for key in [Keys.cellPool, Keys.cellMemory, Keys.halfLives, Keys.tenseLevels, Keys.curriculum,
                    Keys.legacyLevels, Keys.legacyLastMistakes] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Migration

    private struct OldCells: Decodable {
        let cells: [Cell]?
        let unlocked: [Cell]?
    }

    /// Earlier verb×tense cells become the groups and irregular verbs they belong to, so tenses already
    /// reached stay open. What was remembered per verb starts over: it is now measured per group.
    private static func migratedPool(from defaults: UserDefaults, at now: Date) -> LearningPool {
        let old = load(OldCells.self, key: Keys.cellPool, from: defaults) ?? load(OldCells.self, key: Keys.curriculum, from: defaults)
        let cells = (old?.cells ?? []) + (old?.unlocked ?? [])
        return LearningPool(units: LearningPool.startUnits + cells.map { PoolUnit(verb: $0.verb, tense: $0.tense) }, at: now)
    }

    // MARK: Conjugation

    func state(of key: MemoryKey) -> MemoryState? { memory[key] }

    func progress(of unit: PoolUnit) -> LearningPool.Progress { pool.progress(of: unit) }

    /// The ring: progress of the verb's group (or the verb, where it is irregular) in that tense toward performing well,
    /// 0…10. 0 when it is not in the pool yet.
    func level(of verb: String, tense: Tense) -> Int {
        let unit = PoolUnit(verb: verb, tense: tense)
        guard pool.contains(unit) else { return 0 }
        return Int((progress(of: unit).fraction * Double(Self.maxLevel)).rounded(.down))
    }

    /// The ring in every tense the verb has forms in.
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

    /// Records a first answer: on the group pattern (regular forms) or the form (irregular ones), in the
    /// unit's recent answers, and for the statistics, the answer log and the red markers.
    func record(_ item: ConjugationItem, _ rating: Rating) {
        let time = now()
        let key = MemoryKey(verb: item.verb, tense: item.tense, person: item.person)
        let before = memory[key]
        memory.record(key, rating, at: time)
        pool.record(key, rating)
        log.append(AnswerLogEntry(date: time, verb: item.verb, tense: item.tense, person: item.person, gender: item.gender,
                                  rating: rating, retrievabilityBefore: before?.retrievability(at: time) ?? 0,
                                  stabilityBefore: before?.stability, stabilityAfter: memory[key]!.stability))
        if rating == .again { lastMistakes.insert(Self.mistakeKey(item.verb, item.tense)) }
        history.record(verb: item.verb, tense: item.tense, correct: rating != .again, on: time)
    }

    func resetLastMistakes() { lastMistakes = [] }

    /// Ends round 1: reports how the practised units moved since `before` (their shares when the lesson
    /// started) and unlocks what comes after every unit that now performs well.
    func finishLesson(practised: Set<PoolUnit>, before: [PoolUnit: Double]) -> LessonOutcome {
        let changes = pool.units.filter(practised.contains).map {
            LessonOutcome.ProgressChange(unit: $0, from: before[$0], to: progress(of: $0).share)
        }
        return LessonOutcome(changes: changes, additions: pool.finishLesson(at: now()))
    }

    /// A lesson from the whole pool (learning path), or from the given verbs and tenses (free practice).
    func pickLesson(length: Int, verbs: Set<String>? = nil, tenses: Set<Tense>? = nil) -> [FormKey] {
        var rng = SystemRandomNumberGenerator()
        let units = pool.units.filter { unit in
            (tenses?.contains(unit.tense) ?? true) && (verbs.map { !Set(unit.verbs).isDisjoint(with: $0) } ?? true)
        }
        return Curriculum.pickLesson(units: units, verbs: { unit in verbs.map { selected in unit.verbs.filter(selected.contains) } ?? unit.verbs },
                                     pool: pool, memory: memory, length: length, at: now(), using: &rng)
    }

    // MARK: Learning path

    func isUnlocked(verb: String, tense: Tense) -> Bool { pool.contains(PoolUnit(verb: verb, tense: tense)) }

    /// Verbs of the groups and irregular verbs in the pool, in path order.
    var unlockedVerbs: [String] {
        let verbs = Set(pool.units.flatMap(\.verbs))
        return Curriculum.verbOrder.filter(verbs.contains)
    }

    /// A verb's tenses in the pool, in path order.
    func unlockedTenses(of verb: String) -> [Tense] {
        Curriculum.tenseOrder.filter { isUnlocked(verb: verb, tense: $0) }
    }

    /// Tenses in the pool for at least one group or verb, in path order.
    var unlockedTenses: [Tense] {
        let tenses = Set(pool.units.map(\.tense))
        return Curriculum.tenseOrder.filter(tenses.contains)
    }

    /// Free practice may only offer what is in the pool.
    private func keepFreeSelectionUnlocked() {
        var settings = conjugation
        settings.verbs.formIntersection(unlockedVerbs)
        if settings.verbs.isEmpty { settings.verbs = [unlockedVerbs[0]] }
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

    /// Clears memory and progress (both exercises), the learning pool, the recent mistakes, the statistics and
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
