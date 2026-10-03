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

/// What finishing round 1 of a conjugation lesson changed.
struct LessonOutcome {
    struct LevelChange: Identifiable {
        let cell: Cell
        let from: Int
        let to: Int
        var id: Cell { cell }
    }

    let levelChanges: [LevelChange]
    let unlock: Unlock?
}

/// Everything that survives app restarts: exercise settings, mastery levels and the answer history.
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
    /// Mastery 0…10 per verb and tense for the conjugation exercise, keyed by verb, then
    /// `Tense.rawValue`. Changes by at most one step per lesson, judged on the first answers.
    private(set) var tenseLevels: [String: [String: Int]] { didSet { save(tenseLevels, key: Keys.tenseLevels) } }
    /// The verbs and tenses the learning path has unlocked.
    private(set) var curriculum: CurriculumState { didSet { save(curriculum, key: Keys.curriculum) } }
    /// "verb|tense" pairs answered wrong in round 1 of the most recently started lesson (shown in red).
    private(set) var lastMistakes: Set<String> { didSet { save(lastMistakes, key: Keys.lastMistakes) } }
    /// Separate mastery for essere/avere — it measures a different skill. Only first attempts count.
    private(set) var auxLevels: [String: Int] { didSet { save(auxLevels, key: Keys.auxLevels) } }

    /// Every first answer, for the statistics.
    let history: AnswerHistory

    private let defaults: UserDefaults

    private enum Keys {
        static let settings = "coniugazione-settings"
        static let tenseLevels = "coniugazione-tense-levels"
        static let lastMistakes = "coniugazione-tense-mistakes"
        static let curriculum = "coniugazione-curriculum"
        // Per-verb data from before mastery was tracked per tense.
        static let legacyLevels = "coniugazione-levels"
        static let legacyLastMistakes = "coniugazione-last-mistakes"
        static let auxSettings = "coniugazione-aux-settings"
        static let auxLevels = "coniugazione-aux-levels"
    }

    init(defaults: UserDefaults = .standard, historyURL: URL? = AnswerHistory.defaultURL) {
        self.defaults = defaults
        history = AnswerHistory(fileURL: historyURL)
        var conjugation = Self.load(ConjugationSettings.self, key: Keys.settings, from: defaults) ?? ConjugationSettings()
        conjugation.verbs.formIntersection(VerbLibrary.orderedKeys)
        if conjugation.verbs.isEmpty { conjugation.verbs = ConjugationSettings().verbs }
        if conjugation.tenses.isEmpty { conjugation.tenses = [.presente] }
        self.conjugation = conjugation

        var aux = Self.load(AuxSettings.self, key: Keys.auxSettings, from: defaults) ?? AuxSettings()
        aux.verbs.formIntersection(VerbLibrary.orderedKeys)
        if aux.verbs.isEmpty { aux.verbs = Set(VerbLibrary.orderedKeys) }
        self.aux = aux

        let stored = Self.load([String: [String: Int]].self, key: Keys.tenseLevels, from: defaults)
        // Old per-verb levels were earned mostly in the default tense, so they become Presente levels.
        let legacy = Self.load([String: Int].self, key: Keys.legacyLevels, from: defaults) ?? [:]
        let tenseLevels = stored ?? legacy.mapValues { [Tense.presente.rawValue: $0] }
        self.tenseLevels = tenseLevels
        lastMistakes = Self.load(Set<String>.self, key: Keys.lastMistakes, from: defaults) ?? []
        auxLevels = Self.load([String: Int].self, key: Keys.auxLevels, from: defaults) ?? [:]
        let storedCurriculum = Self.load(CurriculumState.self, key: Keys.curriculum, from: defaults)
        curriculum = storedCurriculum ?? .migrated(levels: tenseLevels)
        keepFreeSelectionUnlocked()

        if stored == nil, !legacy.isEmpty { save(tenseLevels, key: Keys.tenseLevels) }
        if storedCurriculum == nil { save(curriculum, key: Keys.curriculum) }
        defaults.removeObject(forKey: Keys.legacyLevels)
        defaults.removeObject(forKey: Keys.legacyLastMistakes)
    }

    // MARK: Conjugation

    func level(of verb: String, tense: Tense) -> Int { tenseLevels[verb]?[tense.rawValue] ?? 0 }

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

    func level(of cell: Cell) -> Int { level(of: cell.verb, tense: cell.tense) }

    /// Records the answer for the statistics and the red markers. Levels change only in `finishFirstRound`.
    func recordFirstAttempt(verb: String, tense: Tense, correct: Bool) {
        if !correct { lastMistakes.insert(Self.mistakeKey(verb, tense)) }
        history.record(verb: verb, tense: tense, correct: correct)
    }

    func resetLastMistakes() { lastMistakes = [] }

    /// Applies one level step per practised cell, then lets the learning path unlock at most one new cell.
    func finishFirstRound(results: [Cell: AnswerCounts]) -> LessonOutcome {
        var changes: [LessonOutcome.LevelChange] = []
        for (cell, counts) in results.sorted(by: { Curriculum.rank($0.key) < Curriculum.rank($1.key) }) {
            let from = level(of: cell)
            let to = min(Self.maxLevel, max(0, from + Curriculum.levelChange(correct: counts.correct, total: counts.total)))
            guard to != from else { continue }
            tenseLevels[cell.verb, default: [:]][cell.tense.rawValue] = to
            changes.append(.init(cell: cell, from: from, to: to))
        }
        guard !results.isEmpty, let unlock = Curriculum.nextUnlock(curriculum, level: level(of:)) else {
            return LessonOutcome(levelChanges: changes, unlock: nil)
        }
        curriculum.apply(unlock)
        return LessonOutcome(levelChanges: changes, unlock: unlock)
    }

    // MARK: Learning path

    func isUnlocked(verb: String, tense: Tense) -> Bool { curriculum.contains(Cell(verb: verb, tense: tense)) }

    /// Unlocked verbs in path order.
    var unlockedVerbs: [String] { Curriculum.verbOrder.filter(curriculum.verbs.contains) }

    /// A verb's unlocked tenses in path order.
    func unlockedTenses(of verb: String) -> [Tense] {
        Curriculum.tenseOrder.filter { isUnlocked(verb: verb, tense: $0) }
    }

    /// Tenses unlocked for at least one verb, in path order.
    var unlockedTenses: [Tense] {
        let tenses = Set(curriculum.unlocked.map(\.tense))
        return Curriculum.tenseOrder.filter(tenses.contains)
    }

    var openCellCount: Int { Curriculum.openCount(curriculum, level: level(of:)) }

    /// Free practice may only offer what the path has unlocked.
    private func keepFreeSelectionUnlocked() {
        var settings = conjugation
        settings.verbs.formIntersection(curriculum.verbs)
        if settings.verbs.isEmpty { settings.verbs = [curriculum.newest.verb] }
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

    /// Clears mastery levels (both exercises), the learning path, the recent mistakes and the statistics.
    /// The other settings are kept; free practice falls back to what is unlocked.
    func resetProgress() {
        tenseLevels = [:]
        curriculum = .initial
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
