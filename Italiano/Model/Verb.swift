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

enum VerbGroup: String, CaseIterable {
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

    /// The m/f hint shown next to a pronoun. lui and lei already say it themselves.
    static func marker(_ person: Int, gender: Gender?) -> String? {
        guard let gender, person != 2 else { return nil }
        return gender.marker
    }
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

/// An irregular verb: everything that cannot be derived is spelled out.
struct IrregularVerbSeed {
    let infinitive: String
    /// The infinitive's ending group (fare → -are, bere → -ere, dire → -ire), for reference only.
    let ending: VerbGroup
    let meaning: String
    /// One German verb for prompts and derived German forms, e.g. "machen" for "machen, tun".
    let germanInfinitive: String
    let presente: [String]
    let imperfetto: [String]
    let futuro: [String]
    let congiuntivo: [String]
    /// `nil` for verbs without an imperative (potere, dovere, volere, piacere).
    let imperativo: [String?]?
    /// Further accepted tu-imperatives by person, e.g. fai next to fa'.
    var imperativoAlternatives: [Int: [String]] = [:]
    let participle: String
    let auxiliary: Auxiliary
    let dePresente: [String]
    let dePraeteritum: [String]
    let deParticiple: String
    let deAuxiliary: GermanAuxiliary
    var deImperative: String = ""
    /// Complete German imperative where the default pattern does not fit (seien sie, gehen sie aus).
    var deImperativo: [String?]? = nil
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
    /// The German verb used in prompts; `meaning` may list several ("machen, tun").
    let germanInfinitive: String
    let isIrregular: Bool
    /// Further accepted answers besides the main form, by tense and person.
    let alternatives: [Tense: [Int: [String]]]
    let participle: String
    let auxiliary: Auxiliary
    /// Indexed by person (0 = io … 5 = loro); `nil` where a form does not exist.
    let italian: [Tense: [String?]]
    let german: [Tense: [String?]]

    var id: String { infinitive }

    func italian(_ tense: Tense, _ person: Int) -> String { italian[tense]?[person] ?? "" }
    func german(_ tense: Tense, _ person: Int) -> String { german[tense]?[person] ?? "" }

    func hasForm(_ tense: Tense, _ person: Int) -> Bool { (italian[tense]?[person] ?? nil) != nil }
    func hasTense(_ tense: Tense) -> Bool { tense.persons.contains { hasForm(tense, $0) } }

    /// "-are", "-ere", … or "unregelmäßig".
    var groupLabel: String { isIrregular ? "unregelmäßig" : group.rawValue }

    /// A form as shown in the conjugation table: both genders where the participle agrees
    /// ("sono andato/a", "siamo andati/e"), and accepted variants ("fa' / fai").
    func tableForm(_ tense: Tense, _ person: Int) -> String? {
        guard hasForm(tense, person) else { return nil }
        let main = italian(tense, person)
        var form = main
        if isGendered(tense) {
            form += "/" + String(italian(tense, person, gender: .feminine).suffix(1))
        }
        // "fa" is only fa' typed without the apostrophe, so it is accepted but not shown.
        for alternative in alternatives[tense]?[person] ?? [] where alternative + "'" != main {
            form += " / \(alternative)"
        }
        return form
    }

    /// Every answer that counts as correct, main form first.
    func acceptedAnswers(_ tense: Tense, _ person: Int, gender: Gender?) -> [String] {
        [italian(tense, person, gender: gender)] + (alternatives[tense]?[person] ?? [])
    }

    /// Only the Passato prossimo with essere agrees with the subject: sono arrivato / arrivata.
    func isGendered(_ tense: Tense) -> Bool { tense == .passatoprossimo && auxiliary == .essere }

    func italian(_ tense: Tense, _ person: Int, gender: Gender?) -> String {
        guard let gender, isGendered(tense) else { return italian(tense, person) }
        return Conjugator.passatoProssimo(participle: participle, auxiliary: auxiliary, gender: gender)[person]
    }

    /// The spelling trap of this verb, if it has one, illustrated with its own forms.
    var spellingNote: String? {
        guard !isIrregular else { return nil }
        let tu = italian(.presente, 1), noi = italian(.presente, 3), futuro = italian(.futuro, 0)
        if Conjugator.stressedIVerbs.contains(infinitive) {
            return "Das i ist betont (io \(italian(.presente, 0))) und bleibt deshalb erhalten: tu \(tu), \(futuro), che loro \(italian(.congiuntivo, 5)). Nur bei noi verschmelzen die beiden i: \(noi)."
        }
        if infinitive.hasSuffix("ciare") || infinitive.hasSuffix("giare") {
            return "Das i macht nur das \(infinitive.hasSuffix("ciare") ? "c" : "g") weich. Vor i und e fällt es weg: tu \(tu), noi \(noi), \(futuro), che loro \(italian(.congiuntivo, 5))."
        }
        if infinitive.hasSuffix("iare") {
            return "Kein doppeltes i: tu \(tu), noi \(noi). Im Futuro bleibt das i: \(futuro)."
        }
        if infinitive.hasSuffix("care") || infinitive.hasSuffix("gare") {
            return "Vor e und i steht ein h, damit der Laut hart bleibt: tu \(tu), \(futuro), che loro \(italian(.congiuntivo, 5))."
        }
        return nil
    }

    init(seed: VerbSeed) {
        infinitive = seed.infinitive
        group = seed.group
        meaning = seed.meaning
        germanInfinitive = seed.meaning
        isIrregular = false
        alternatives = [:]
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

    init(irregular seed: IrregularVerbSeed) {
        infinitive = seed.infinitive
        group = seed.ending
        meaning = seed.meaning
        germanInfinitive = seed.germanInfinitive
        isIrregular = true
        alternatives = seed.imperativoAlternatives.isEmpty ? [:] : [.imperativo: seed.imperativoAlternatives]
        participle = seed.participle
        auxiliary = seed.auxiliary

        italian = [
            .presente: seed.presente,
            .passatoprossimo: Conjugator.passatoProssimo(participle: seed.participle, auxiliary: seed.auxiliary),
            .imperfetto: seed.imperfetto,
            .futuro: seed.futuro,
            .condizionale: Conjugator.condizionale(futuro: seed.futuro),
            .congiuntivo: seed.congiuntivo,
            .imperativo: seed.imperativo ?? Array(repeating: nil, count: 6),
        ]
        let deInfinitive = seed.germanInfinitive
        german = [
            .presente: seed.dePresente,
            .passatoprossimo: Conjugator.perfekt(participle: seed.deParticiple, auxiliary: seed.deAuxiliary,
                                                 reflexiveInfinitive: deInfinitive),
            .imperfetto: seed.dePraeteritum,
            .futuro: Conjugator.werde(infinitive: deInfinitive),
            .condizionale: Conjugator.wuerde(infinitive: deInfinitive),
            .congiuntivo: seed.dePresente,
            .imperativo: seed.imperativo == nil ? Array(repeating: nil, count: 6)
                : seed.deImperativo ?? Conjugator.deImperativ(duForm: seed.deImperative, presente: seed.dePresente,
                                                              infinitive: deInfinitive),
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
    static let werdeForms = ["werde", "wirst", "wird", "werden", "werdet", "werden"]
    static let reflexivePronouns = ["mich", "dich", "sich", "uns", "euch", "sich"]
    /// -iare verbs whose i is stressed (io scìo) and therefore kept before i and e.
    static let stressedIVerbs: Set<String> = ["sciare", "inviare", "spiare", "avviare"]

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

    static func passatoProssimo(participle: String, auxiliary: Auxiliary, gender: Gender = .masculine) -> [String] {
        let forms = auxiliary == .essere ? esserePresente : averePresente
        guard auxiliary == .essere else { return forms.map { "\($0) \(participle)" } }
        // With essere the participle agrees with the subject: arrivato/arrivata, arrivati/arrivate.
        let stem = String(participle.dropLast())
        let singular = stem + (gender == .masculine ? "o" : "a")
        let plural = stem + (gender == .masculine ? "i" : "e")
        let participles = [singular, singular, singular, plural, plural, plural]
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

    /// With a reflexive infinitive ("sich befinden") the pronoun follows the auxiliary:
    /// "habe mich befunden".
    static func perfekt(participle: String, auxiliary: GermanAuxiliary, reflexiveInfinitive: String = "") -> [String] {
        let reflexive = reflexiveInfinitive.hasPrefix("sich ")
        return (auxiliary == .sein ? seinPraesens : habenPraesens).enumerated().map { person, aux in
            reflexive ? "\(aux) \(reflexivePronouns[person]) \(participle)" : "\(aux) \(participle)"
        }
    }

    static func wuerde(infinitive: String) -> [String] { compound(wuerdeForms, infinitive) }
    static func werde(infinitive: String) -> [String] { compound(werdeForms, infinitive) }

    /// Auxiliary + infinitive, moving a reflexive "sich" to the right person: "werde mich befinden".
    private static func compound(_ auxiliaries: [String], _ infinitive: String) -> [String] {
        guard infinitive.hasPrefix("sich ") else { return auxiliaries.map { "\($0) \(infinitive)" } }
        let verb = infinitive.dropFirst("sich ".count)
        return auxiliaries.enumerated().map { "\($1) \(reflexivePronouns[$0]) \(verb)" }
    }

    static func deImperativ(duForm: String, presente: [String], infinitive: String) -> [String?] {
        [nil, duForm, "\(infinitive) sie", "\(infinitive) wir", presente[4], "\(infinitive) sie"]
    }
}

enum VerbLibrary {
    static let all: [String: Verb] = {
        let regular: [Verb] = VerbCatalog.seeds.map { Verb(seed: $0) }
        let irregular: [Verb] = IrregularVerbCatalog.seeds.map { Verb(irregular: $0) }
        return Dictionary(uniqueKeysWithValues: (regular + irregular).map { ($0.infinitive, $0) })
    }()
    static let irregularKeys: [String] = IrregularVerbCatalog.seeds.map(\.infinitive).sorted()
    static let orderedKeys: [String] = VerbCatalog.seeds.map(\.infinitive) + irregularKeys

    /// The verb picker's sections: the regular groups, then all irregular verbs alphabetically.
    static let groups: [VerbGroupSection] =
        VerbCatalog.groups + [VerbGroupSection(label: "Unregelmäßig", verbs: irregularKeys)]

    static func verb(_ key: String) -> Verb { all[key]! }
}
