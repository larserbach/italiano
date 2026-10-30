import Foundation
import Observation

/// Everything that survives app restarts: exercise settings, what the learner remembers, the learning pool
/// and the answer history.
@Observable
final class ProgressStore {
    /// The full ring, for the learning-path levels and the essere/avere levels alike.
    static let maxLevel = 10

    var conjugation: ConjugationSettings { didSet { save(conjugation, key: Keys.settings) } }
    var aux: AuxSettings { didSet { save(aux, key: Keys.auxSettings) } }
    /// Whether Italian forms are read aloud, in both exercises.
    var readAloud: Bool { didSet { save(readAloud, key: Keys.readAloud) } }
    /// Difficulty, stability and retrievability per group pattern and irregular form. Updated after every first answer.
    private(set) var memory: LearningMemory { didSet { save(memory, key: Keys.memory) } }
    /// The groups and irregular verbs in play, per tense.
    private(set) var pool: LearningPool { didSet { save(pool, key: Keys.pool) } }
    /// Separate mastery for essere/avere — it measures a different skill. Only first attempts count, each
    /// moving the verb's level one step up or down.
    private(set) var auxLevels: [String: Int] { didSet { save(auxLevels, key: Keys.auxLevels) } }

    /// Every first answer, aggregated per day for the statistics.
    let history: AnswerHistory
    /// Every first answer with its effect on memory, for the progress screens of groups and irregular verbs.
    let log: AnswerLog
    /// The clock for everything time-based; tests replace it.
    let now: () -> Date

    private let defaults: UserDefaults

    private enum Keys {
        static let settings = "coniugazione-settings"
        static let memory = "coniugazione-group-memory"
        static let pool = "coniugazione-group-pool"
        static let auxSettings = "coniugazione-aux-settings"
        static let auxLevels = "coniugazione-aux-levels"
        static let readAloud = "read-aloud"
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
        // The red marks of the last lesson's mistakes, shown in free practice.
        static let lastMistakes = "coniugazione-tense-mistakes"
    }

    init(defaults: UserDefaults = .standard, historyURL: URL? = AnswerHistory.defaultURL,
         logURL: URL? = AnswerLog.defaultURL, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        history = AnswerHistory(fileURL: historyURL)
        log = AnswerLog(fileURL: logURL)
        conjugation = Self.load(ConjugationSettings.self, key: Keys.settings, from: defaults) ?? ConjugationSettings()

        var aux = Self.load(AuxSettings.self, key: Keys.auxSettings, from: defaults) ?? AuxSettings()
        aux.verbs.formIntersection(VerbLibrary.orderedKeys)
        if aux.verbs.isEmpty { aux.verbs = Set(VerbLibrary.orderedKeys) }
        self.aux = aux
        readAloud = Self.load(Bool.self, key: Keys.readAloud, from: defaults) ?? true

        auxLevels = Self.load([String: Int].self, key: Keys.auxLevels, from: defaults) ?? [:]
        let start = now()
        memory = Self.load(LearningMemory.self, key: Keys.memory, from: defaults) ?? LearningMemory()
        let storedPool = Self.load(LearningPool.self, key: Keys.pool, from: defaults)
        var pool = storedPool ?? Self.migratedPool(from: defaults, at: start)
        pool.dropInvalidUnits()
        self.pool = pool

        // `didSet` doesn't run for assignments in init, so a migrated or cleaned-up pool is saved here.
        if storedPool != pool { save(pool, key: Keys.pool) }
        for key in [Keys.cellPool, Keys.cellMemory, Keys.halfLives, Keys.tenseLevels, Keys.curriculum,
                    Keys.legacyLevels, Keys.legacyLastMistakes, Keys.lastMistakes] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Migration

    private struct OldCells: Decodable {
        /// One verb in one tense.
        struct Cell: Decodable {
            let verb: String
            let tense: Tense
        }

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

    /// Records a first answer: on the group pattern (regular forms) or the form (irregular ones), in the
    /// unit's recent answers, and for the statistics and the answer log.
    func record(_ item: ConjugationItem, _ rating: Rating) {
        let time = now()
        let key = MemoryKey(verb: item.verb, tense: item.tense, person: item.person)
        let before = memory[key]
        memory.record(key, rating, at: time)
        pool.record(key, rating)
        log.append(AnswerLogEntry(date: time, verb: item.verb, tense: item.tense, person: item.person, gender: item.gender,
                                  rating: rating, retrievabilityBefore: before?.retrievability(at: time) ?? 0,
                                  stabilityBefore: before?.stability, stabilityAfter: memory[key]!.stability))
        history.record(verb: item.verb, tense: item.tense, correct: rating != .again, on: time)
    }

    /// Ends round 1: reports how the practised units moved since `before` (their shares when the lesson
    /// started) and unlocks what comes after every unit that now performs well.
    func finishLesson(practised: Set<PoolUnit>, before: [PoolUnit: Double]) -> LessonOutcome {
        let changes = pool.units.filter(practised.contains).map {
            LessonOutcome.ProgressChange(unit: $0, from: before[$0], to: progress(of: $0).share)
        }
        return LessonOutcome(changes: changes, additions: pool.finishLesson(at: now()))
    }

    /// A lesson from the whole pool.
    func pickLesson(length: Int) -> [FormKey] {
        var rng = SystemRandomNumberGenerator()
        return Curriculum.pickLesson(units: pool.units, verbs: pool.verbs(of:),
                                     memory: memory, length: length, at: now(), using: &rng)
    }

    // MARK: Essere o avere

    func auxLevel(of verb: String) -> Int { auxLevels[verb] ?? 0 }

    func recordAuxAnswer(verb: String, correct: Bool) {
        auxLevels[verb] = Self.step(auxLevel(of: verb), correct: correct)
    }

    // MARK: Reset

    /// Clears memory and progress (both exercises), the learning pool, the statistics and the answer log.
    /// The settings are kept.
    func resetProgress() {
        memory = LearningMemory()
        log.reset()
        pool = .initial(at: now())
        auxLevels = [:]
        history.reset()
    }

    // MARK: Helpers

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
