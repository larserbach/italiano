import Foundation
import Observation

enum Direction: String, CaseIterable, Codable, Identifiable {
    case italian = "it", german = "de", mixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .italian: "Italienisch zeigen"
        case .german: "Deutsch zeigen"
        case .mixed: "Gemischt"
        }
    }
}

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

/// Everything that survives app restarts: lesson settings and per-verb mastery levels.
@Observable
final class ProgressStore {
    static let maxLevel = 10

    struct ConjugationSettings: Codable {
        var verbs: Set<String> = Set(VerbLibrary.orderedKeys)
        var tenses: Set<Tense> = [.presente]
        var direction: Direction = .italian
        var length: LessonLength = .count(5)
    }

    struct AuxSettings: Codable {
        var verbs: Set<String> = Set(VerbLibrary.orderedKeys)
        var length: LessonLength = .count(10)
    }

    var conjugation: ConjugationSettings { didSet { save(conjugation, key: Keys.settings) } }
    var aux: AuxSettings { didSet { save(aux, key: Keys.auxSettings) } }
    /// Mastery 0…10 per verb and tense for the conjugation exercise, keyed by verb, then
    /// `Tense.rawValue`. Only first-round answers count.
    private(set) var tenseLevels: [String: [String: Int]] { didSet { save(tenseLevels, key: Keys.tenseLevels) } }
    /// "verb|tense" pairs answered wrong in round 1 of the most recently started lesson (shown in red).
    private(set) var lastMistakes: Set<String> { didSet { save(lastMistakes, key: Keys.lastMistakes) } }
    /// Separate mastery for essere/avere — it measures a different skill.
    private(set) var auxLevels: [String: Int] { didSet { save(auxLevels, key: Keys.auxLevels) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let settings = "coniugazione-settings"
        static let tenseLevels = "coniugazione-tense-levels"
        static let lastMistakes = "coniugazione-tense-mistakes"
        // Per-verb data from before mastery was tracked per tense.
        static let legacyLevels = "coniugazione-levels"
        static let legacyLastMistakes = "coniugazione-last-mistakes"
        static let auxSettings = "coniugazione-aux-settings"
        static let auxLevels = "coniugazione-aux-levels"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var conjugation = Self.load(ConjugationSettings.self, key: Keys.settings, from: defaults) ?? ConjugationSettings()
        conjugation.verbs.formIntersection(VerbLibrary.orderedKeys)
        if conjugation.verbs.isEmpty { conjugation.verbs = Set(VerbLibrary.orderedKeys) }
        if conjugation.tenses.isEmpty { conjugation.tenses = [.presente] }
        self.conjugation = conjugation

        var aux = Self.load(AuxSettings.self, key: Keys.auxSettings, from: defaults) ?? AuxSettings()
        aux.verbs.formIntersection(VerbLibrary.orderedKeys)
        if aux.verbs.isEmpty { aux.verbs = Set(VerbLibrary.orderedKeys) }
        self.aux = aux

        let stored = Self.load([String: [String: Int]].self, key: Keys.tenseLevels, from: defaults)
        // Old per-verb levels were earned mostly in the default tense, so they become Presente levels.
        let legacy = Self.load([String: Int].self, key: Keys.legacyLevels, from: defaults) ?? [:]
        tenseLevels = stored ?? legacy.mapValues { [Tense.presente.rawValue: $0] }
        lastMistakes = Self.load(Set<String>.self, key: Keys.lastMistakes, from: defaults) ?? []
        auxLevels = Self.load([String: Int].self, key: Keys.auxLevels, from: defaults) ?? [:]

        if stored == nil, !legacy.isEmpty { save(tenseLevels, key: Keys.tenseLevels) }
        defaults.removeObject(forKey: Keys.legacyLevels)
        defaults.removeObject(forKey: Keys.legacyLastMistakes)
    }

    // MARK: Conjugation

    func level(of verb: String, tense: Tense) -> Int { tenseLevels[verb]?[tense.rawValue] ?? 0 }

    /// What a verb chip's ring shows: the average over the given tenses, rounded down.
    func level(of verb: String, tenses: Set<Tense>) -> Int {
        guard !tenses.isEmpty else { return 0 }
        return tenses.map { level(of: verb, tense: $0) }.reduce(0, +) / tenses.count
    }

    func isRecentMistake(verb: String, tenses: Set<Tense>) -> Bool {
        tenses.contains { lastMistakes.contains(Self.mistakeKey(verb, $0)) }
    }

    func recordFirstAttempt(verb: String, tense: Tense, correct: Bool) {
        tenseLevels[verb, default: [:]][tense.rawValue] = Self.step(level(of: verb, tense: tense), correct: correct)
        if !correct { lastMistakes.insert(Self.mistakeKey(verb, tense)) }
    }

    func resetLastMistakes() { lastMistakes = [] }

    // MARK: Essere o avere

    func auxLevel(of verb: String) -> Int { auxLevels[verb] ?? 0 }

    func recordAuxAnswer(verb: String, correct: Bool) {
        auxLevels[verb] = Self.step(auxLevel(of: verb), correct: correct)
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
