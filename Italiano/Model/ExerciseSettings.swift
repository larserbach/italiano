import Foundation

/// How many questions a lesson asks.
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

    /// The number of questions out of a pool of `poolSize`.
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

extension ProgressStore {
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
