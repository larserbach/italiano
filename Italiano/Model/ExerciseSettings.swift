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

extension ProgressStore {
    struct ConjugationSettings: Codable {
        var length: LessonLength = .count(5)
    }

    struct AuxSettings: Codable {
        var verbs: Set<String> = Set(VerbLibrary.orderedKeys)
        var length: LessonLength = .count(10)
    }
}

extension ProgressStore.ConjugationSettings {
    /// Settings saved before a field existed still load, with that field's default. Fields of free practice
    /// (mode, verbs, tenses) in older settings are ignored.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        length = try container.decodeIfPresent(LessonLength.self, forKey: .length) ?? length
    }
}
