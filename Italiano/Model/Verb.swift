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

/// One section of the verb picker.
struct VerbGroupSection: Identifiable {
    let label: String
    let verbs: [String]
    var id: String { label }
}

/// A verb with all its forms in both languages, built once from its seed.
struct Verb: Identifiable {
    let infinitive: String
    let group: VerbGroup
    let meaning: String
    /// The German verb used in prompts; `meaning` may list several ("machen, tun").
    let germanInfinitive: String
    /// Tenses whose forms do not follow the verb's ending group, worked out from the forms themselves:
    /// scrivere is regular in the Presente (counts for -ere) but not in the Passato prossimo (scritto).
    let irregularTenses: Set<Tense>
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

    func isIrregular(in tense: Tense) -> Bool { irregularTenses.contains(tense) }

    /// Regular in no tense it has.
    var isFullyIrregular: Bool { Tense.allCases.filter(hasTense).allSatisfy(irregularTenses.contains) }

    /// "-are", "unregelmäßig", or the group with the tenses that leave it ("-ere · unregelmäßig: Pass. pr.").
    var groupLabel: String {
        if isFullyIrregular { return "unregelmäßig" }
        let tenses = Curriculum.tenseOrder.filter(irregularTenses.contains)
        guard !tenses.isEmpty else { return group.rawValue }
        return "\(group.rawValue) · unregelmäßig: " + tenses.map(\.shortLabel).joined(separator: ", ")
    }

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
        guard !isIrregular(in: .presente) else { return nil }
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
        // Regular seeds have a single German meaning.
        germanInfinitive = seed.meaning
        alternatives = [:]
        participle = seed.participle
        auxiliary = seed.auxiliary

        let congiuntivo = Conjugator.congiuntivo(infinitive: seed.infinitive, group: seed.group)
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
        irregularTenses = Conjugator.irregularTenses(infinitive: seed.infinitive, group: seed.group,
                                                     participle: seed.participle, forms: italian)
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
        irregularTenses = Conjugator.irregularTenses(infinitive: seed.infinitive, group: seed.ending,
                                                     participle: seed.participle, forms: italian)
                          .union(seed.imperativoAlternatives.isEmpty ? [] : [.imperativo])
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

/// Every verb in the app, by infinitive.
enum VerbLibrary {
    static let all: [String: Verb] = {
        let regular: [Verb] = VerbCatalog.seeds.map { Verb(seed: $0) }
        let irregular: [Verb] = IrregularVerbCatalog.seeds.map { Verb(irregular: $0) }
        return Dictionary(uniqueKeysWithValues: (regular + irregular).map { ($0.infinitive, $0) })
    }()
    static let irregularKeys: [String] = IrregularVerbCatalog.seeds.map(\.infinitive).sorted()
    /// The regular catalog in its own order, then the irregular verbs alphabetically.
    static let orderedKeys: [String] = VerbCatalog.seeds.map(\.infinitive) + irregularKeys

    /// The verb picker's sections: each verb with its ending group (-are split by auxiliary), unless it is
    /// already irregular in the Presente; those come last.
    static let groups: [VerbGroupSection] = {
        let verbs = orderedKeys.map(verb)
        func section(_ label: String, _ belongs: (Verb) -> Bool) -> VerbGroupSection {
            VerbGroupSection(label: label, verbs: verbs.filter { !$0.isIrregular(in: .presente) && belongs($0) }.map(\.infinitive))
        }
        return [
            section("-are · mit avere im Passato prossimo") { $0.group == .are && $0.auxiliary == .avere },
            section("-are · mit essere im Passato prossimo") { $0.group == .are && $0.auxiliary == .essere },
            section("-ere") { $0.group == .ere },
            section("-ire") { $0.group == .ire },
            section("-ire · mit -isc-") { $0.group == .ireIsc },
            VerbGroupSection(label: "Unregelmäßig", verbs: verbs.filter { $0.isIrregular(in: .presente) }.map(\.infinitive)),
        ].filter { !$0.verbs.isEmpty }
    }()

    static func verb(_ key: String) -> Verb { all[key]! }
}
