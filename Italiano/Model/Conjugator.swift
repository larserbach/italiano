import Foundation

/// Builds the forms that follow from rules, in Italian and German, for the seeds and for the answer check.
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
        // -are verbs take an e in the Futuro: parlerò.
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

    /// The du form as given, ihr from the Präsens, and the infinitive with sie (formal address) or wir.
    static func deImperativ(duForm: String, presente: [String], infinitive: String) -> [String?] {
        [nil, duForm, "\(infinitive) sie", "\(infinitive) wir", presente[4], "\(infinitive) sie"]
    }
}
