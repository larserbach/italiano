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

    private static let presenteEndings: [VerbGroup: [String]] = [
        .are: ["o", "i", "a", "iamo", "ate", "ano"],
        .ere: ["o", "i", "e", "iamo", "ete", "ono"],
        .ire: ["o", "i", "e", "iamo", "ite", "ono"],
        .ireIsc: ["isco", "isci", "isce", "iamo", "ite", "iscono"],
    ]
    private static let congiuntivoEndings: [VerbGroup: [String]] = [
        .are: ["i", "i", "i", "iamo", "iate", "ino"],
        .ere: ["a", "a", "a", "iamo", "iate", "ano"],
        .ire: ["a", "a", "a", "iamo", "iate", "ano"],
        .ireIsc: ["isca", "isca", "isca", "iamo", "iate", "iscano"],
    ]
    private static let imperfettoEndings = ["vo", "vi", "va", "vamo", "vate", "vano"]
    private static let futuroEndings = ["rò", "rai", "rà", "remo", "rete", "ranno"]

    /// The infinitive's vowel as used in the Imperfetto, Futuro and participle: a, e or i.
    private static func vowel(_ group: VerbGroup) -> String {
        switch group {
        case .are: "a"
        case .ere: "e"
        case .ire, .ireIsc: "i"
        }
    }

    /// Stem + ending with the spelling rules regular verbs follow: an h keeps c and g hard before e and i
    /// (manchi, mancherò), the stem's i merges with an ending's i (viaggi, but scii where the i is
    /// stressed) and only softens c and g, so it drops before e (viaggerò). Without `spellingRules` the
    /// parts are just put together, which gives the traps learners fall into (pagerò, viaggierò).
    static func join(_ stem: String, _ ending: String, group: VerbGroup, infinitive: String, spellingRules: Bool = true) -> String {
        guard group == .are, spellingRules else { return stem + ending }
        let stressed = stressedIVerbs.contains(infinitive)
        if stem.hasSuffix("c") || stem.hasSuffix("g"), ending.hasPrefix("e") || ending.hasPrefix("i") {
            return stem + "h" + ending
        }
        if stem.hasSuffix("i"), ending.hasPrefix("i"), !stressed || ending.hasPrefix("iam") || ending.hasPrefix("iat") {
            return stem + ending.dropFirst()
        }
        if stem.hasSuffix("ci") || stem.hasSuffix("gi"), ending.hasPrefix("e"), !stressed {
            return stem.dropLast() + ending
        }
        return stem + ending
    }

    /// Every form as the ending group's rules build it from the infinitive.
    static func regularForms(infinitive: String, group: VerbGroup, spellingRules: Bool = true) -> [Tense: [String?]] {
        let stem = String(infinitive.dropLast(3))
        func forms(_ endings: [String]) -> [String] {
            endings.map { join(stem, $0, group: group, infinitive: infinitive, spellingRules: spellingRules) }
        }
        let presente = forms(presenteEndings[group]!)
        let congiuntivo = congiuntivo(infinitive: infinitive, group: group, spellingRules: spellingRules)
        let futuro = forms(futuroEndings.map { (group == .are ? "e" : vowel(group)) + $0 })
        return [
            .presente: presente,
            .passatoprossimo: passatoProssimo(participle: regularParticiple(infinitive: infinitive, group: group), auxiliary: .avere),
            .imperfetto: forms(imperfettoEndings.map { vowel(group) + $0 }),
            .futuro: futuro,
            .condizionale: condizionale(futuro: futuro),
            .congiuntivo: congiuntivo,
            .imperativo: imperativo(infinitive: infinitive, group: group, presente: presente, congiuntivo: congiuntivo),
        ]
    }

    /// parlato, creduto, dormito; -cere keeps the c soft: conosciuto, piaciuto.
    static func regularParticiple(infinitive: String, group: VerbGroup) -> String {
        let stem = String(infinitive.dropLast(3))
        switch group {
        case .are: return stem + "ato"
        case .ere: return stem + (stem.hasSuffix("c") ? "iuto" : "uto")
        case .ire, .ireIsc: return stem + "ito"
        }
    }

    /// The tenses in which `forms` differ from what the group's rules give. In the Passato prossimo only
    /// the participle counts; essere or avere is a question of its own.
    static func irregularTenses(infinitive: String, group: VerbGroup, participle: String, forms: [Tense: [String?]]) -> Set<Tense> {
        let regular = regularForms(infinitive: infinitive, group: group)
        return Set(Tense.allCases.filter { tense in
            if tense == .passatoprossimo { return participle != regularParticiple(infinitive: infinitive, group: group) }
            let own = forms[tense] ?? []
            return own.indices.contains { person in own[person].map { $0 != regular[tense]?[person] } ?? false }
        })
    }

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

    static func congiuntivo(infinitive: String, group: VerbGroup, spellingRules: Bool = true) -> [String] {
        let stem = String(infinitive.dropLast(3))
        return congiuntivoEndings[group]!.map { join(stem, $0, group: group, infinitive: infinitive, spellingRules: spellingRules) }
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
