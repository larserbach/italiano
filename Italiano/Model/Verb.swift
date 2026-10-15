import Foundation

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
