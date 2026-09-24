import Foundation

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

    /// Person indices that exist in this tense (there is no io-form of the imperative).
    var persons: Range<Int> { self == .imperativo ? 1..<6 : 0..<6 }
}

enum VerbGroup: String {
    case are = "-are"
    case ere = "-ere"
    case ire = "-ire"
    case ireIsc = "-ire (isc)"
}

enum Auxiliary: String {
    case avere, essere
}

enum GermanAuxiliary: String {
    case haben, sein
}

enum Pronoun {
    static let italian = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
    static let german = ["ich", "du", "er/sie", "wir", "ihr", "sie"]
}

/// The hand-maintained part of a verb; everything else is derived in `Verb.init`.
struct VerbSeed {
    let infinitive: String
    let group: VerbGroup
    let meaning: String
    let presente: [String]
    let imperfetto: [String]
    let futuro: [String]
    let dePresente: [String]
    let deImperfetto: [String]
    let deFuturo: [String]
    let participle: String
    let auxiliary: Auxiliary
    let deParticiple: String
    let deAuxiliary: GermanAuxiliary
    /// The German du-imperative cannot be derived mechanically (vowel changes etc.).
    let deImperative: String
}

struct VerbGroupSection: Identifiable {
    let label: String
    let verbs: [String]
    var id: String { label }
}

struct Verb: Identifiable {
    let infinitive: String
    let group: VerbGroup
    let meaning: String
    let participle: String
    let auxiliary: Auxiliary
    /// Indexed by person (0 = io … 5 = loro); `nil` where a form does not exist.
    let italian: [Tense: [String?]]
    let german: [Tense: [String?]]

    var id: String { infinitive }

    func italian(_ tense: Tense, _ person: Int) -> String { italian[tense]?[person] ?? "" }
    func german(_ tense: Tense, _ person: Int) -> String { german[tense]?[person] ?? "" }

    init(seed: VerbSeed) {
        infinitive = seed.infinitive
        group = seed.group
        meaning = seed.meaning
        participle = seed.participle
        auxiliary = seed.auxiliary

        let congiuntivo = Conjugator.congiuntivoOverrides[seed.infinitive]
            ?? Conjugator.congiuntivo(infinitive: seed.infinitive, group: seed.group)
        italian = [
            .presente: seed.presente,
            .passatoprossimo: Conjugator.passatoProssimo(participle: seed.participle, auxiliary: seed.auxiliary),
            .imperfetto: seed.imperfetto,
            .futuro: seed.futuro,
            .condizionale: Conjugator.condizionale(futuro: seed.futuro),
            .congiuntivo: congiuntivo,
            .imperativo: Conjugator.imperativo(infinitive: seed.infinitive, group: seed.group,
                                               presente: seed.presente, congiuntivo: congiuntivo),
        ]
        german = [
            .presente: seed.dePresente,
            .passatoprossimo: Conjugator.perfekt(participle: seed.deParticiple, auxiliary: seed.deAuxiliary),
            .imperfetto: seed.deImperfetto,
            .futuro: seed.deFuturo,
            .condizionale: Conjugator.wuerde(infinitive: seed.meaning),
            // German mostly uses the plain indicative where Italian needs the congiuntivo.
            .congiuntivo: seed.dePresente,
            .imperativo: Conjugator.deImperativ(duForm: seed.deImperative, presente: seed.dePresente,
                                                infinitive: seed.meaning),
        ]
    }
}

enum Conjugator {
    static let averePresente = ["ho", "hai", "ha", "abbiamo", "avete", "hanno"]
    static let esserePresente = ["sono", "sei", "è", "siamo", "siete", "sono"]
    static let habenPraesens = ["habe", "hast", "hat", "haben", "habt", "haben"]
    static let seinPraesens = ["bin", "bist", "ist", "sind", "seid", "sind"]
    static let condizionaleEndings = ["ei", "esti", "ebbe", "emmo", "este", "ebbero"]
    static let wuerdeForms = ["würde", "würdest", "würde", "würden", "würdet", "würden"]

    /// Spellings the stem + ending rule gets wrong (soft -gi-, -c(h)- before e/i).
    static let congiuntivoOverrides: [String: [String]] = [
        "viaggiare": ["viaggi", "viaggi", "viaggi", "viaggiamo", "viaggiate", "viaggino"],
        "passeggiare": ["passeggi", "passeggi", "passeggi", "passeggiamo", "passeggiate", "passeggino"],
        "mancare": ["manchi", "manchi", "manchi", "manchiamo", "manchiate", "manchino"],
        "sciare": ["scii", "scii", "scii", "sciamo", "sciate", "sciino"],
    ]

    static func auxiliaryForm(_ auxiliary: Auxiliary, person: Int) -> String {
        (auxiliary == .essere ? esserePresente : averePresente)[person]
    }

    static func passatoProssimo(participle: String, auxiliary: Auxiliary) -> [String] {
        let forms = auxiliary == .essere ? esserePresente : averePresente
        guard auxiliary == .essere else { return forms.map { "\($0) \(participle)" } }
        // With essere the participle agrees with the subject (shown masculine here).
        let plural = String(participle.dropLast()) + "i"
        let participles = [participle, participle, participle, plural, plural, plural]
        return zip(forms, participles).map { "\($0) \($1)" }
    }

    static func condizionale(futuro: [String]) -> [String] {
        let stem = String(futuro[0].dropLast()) // strip the final "ò"
        return condizionaleEndings.map { stem + $0 }
    }

    static func congiuntivo(infinitive: String, group: VerbGroup) -> [String] {
        let stem = String(infinitive.dropLast(3))
        switch group {
        case .are:
            return ["i", "i", "i", "iamo", "iate", "ino"].map { stem + $0 }
        case .ireIsc:
            return ["isca", "isca", "isca", "iamo", "iate", "iscano"].map { stem + $0 }
        case .ere, .ire:
            return ["a", "a", "a", "iamo", "iate", "ano"].map { stem + $0 }
        }
    }

    /// lui/lei and loro stand for the formal address (Lei/Loro) and borrow the congiuntivo form.
    static func imperativo(infinitive: String, group: VerbGroup, presente: [String], congiuntivo: [String]) -> [String?] {
        let tu = group == .are ? String(infinitive.dropLast(3)) + "a" : presente[1]
        return [nil, tu, congiuntivo[0], presente[3], presente[4], congiuntivo[5]]
    }

    static func perfekt(participle: String, auxiliary: GermanAuxiliary) -> [String] {
        (auxiliary == .sein ? seinPraesens : habenPraesens).map { "\($0) \(participle)" }
    }

    static func wuerde(infinitive: String) -> [String] {
        wuerdeForms.map { "\($0) \(infinitive)" }
    }

    static func deImperativ(duForm: String, presente: [String], infinitive: String) -> [String?] {
        [nil, duForm, "\(infinitive) sie", "\(infinitive) wir", presente[4], "\(infinitive) sie"]
    }
}

enum VerbLibrary {
    static let all: [String: Verb] = Dictionary(
        uniqueKeysWithValues: VerbCatalog.seeds.map { ($0.infinitive, Verb(seed: $0)) }
    )
    static let orderedKeys: [String] = VerbCatalog.seeds.map(\.infinitive)

    static func verb(_ key: String) -> Verb { all[key]! }
}
