import Foundation

/// In display order; `Curriculum.tenseOrder` is the order they come into the learning path.
enum Tense: String, CaseIterable, Codable, Identifiable {
    case presente, passatoprossimo, imperfetto, futuro, condizionale, congiuntivo, imperativo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .presente: "Presente indicativo"
        case .passatoprossimo: "Passato prossimo"
        case .imperfetto: "Imperfetto"
        case .futuro: "Futuro semplice"
        case .condizionale: "Condizionale presente"
        case .congiuntivo: "Congiuntivo presente"
        case .imperativo: "Imperativo"
        }
    }

    /// For tight spaces such as the learning-path overview.
    var shortLabel: String {
        switch self {
        case .presente: "Pres."
        case .passatoprossimo: "Pass. pr."
        case .imperfetto: "Imperf."
        case .futuro: "Futuro"
        case .condizionale: "Cond."
        case .congiuntivo: "Cong."
        case .imperativo: "Imper."
        }
    }

    /// Person indices that exist in this tense (there is no io-form of the imperative).
    var persons: Range<Int> { self == .imperativo ? 1..<6 : 0..<6 }
}

/// The ending group whose rules a verb's regular forms follow. The raw values are display labels.
enum VerbGroup: String, CaseIterable {
    case are = "-are"
    case ere = "-ere"
    case ire = "-ire"
    case ireIsc = "-ire (isc)"
}

enum Auxiliary: String, Codable {
    case avere, essere
}

enum GermanAuxiliary: String {
    case haben, sein
}

/// The subject's gender, for the few forms that agree with it. Masculine also stands
/// for mixed groups in the plural.
enum Gender: String, CaseIterable, Codable {
    case masculine, feminine

    var marker: String { self == .masculine ? "m" : "f" }
    var spokenName: String { self == .masculine ? "männlich" : "weiblich" }
}

enum Pronoun {
    static let italian = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
    static let german = ["ich", "du", "er/sie", "wir", "ihr", "sie"]

    /// With a known gender, the 3rd person singular becomes lui or lei.
    static func italian(_ person: Int, gender: Gender?) -> String {
        guard person == 2, let gender else { return italian[person] }
        return gender == .masculine ? "lui" : "lei"
    }

    static func german(_ person: Int, gender: Gender?) -> String {
        guard person == 2, let gender else { return german[person] }
        return gender == .masculine ? "er" : "sie"
    }
}
