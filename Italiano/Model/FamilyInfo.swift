/// The explanation sheet for a regular group: how it builds its forms, example verbs to see the endings on,
/// and what to watch out for. The fixed texts are in FamilyInfo+Content.swift; which verbs have a spelling
/// trap, essere, an own participle or own forms in other tenses comes from the catalog.
struct FamilyInfo {
    /// The fixed texts of one group.
    struct Texts {
        let formation: [TenseInfo.ListItem]
        let caveats: [TenseInfo.ListItem]
    }

    /// Under the title.
    let summary: String
    let formation: [TenseInfo.ListItem]
    /// Verbs regular in every tense, in path order. The first has no spelling trap and takes avere, so its
    /// endings show plainly; it is the one shown when the sheet opens.
    let examples: [String]
    /// What to watch out for.
    let sections: [TenseInfo.Section]

    static let maxExamples = 8

    static func of(_ family: VerbFamily) -> FamilyInfo {
        let texts = texts[family]!
        let verbs = family.verbs.map(VerbLibrary.verb)
        let regular = verbs.filter { $0.irregularTenses.isEmpty }
        let model = regular.first { $0.spellingNote == nil && $0.auxiliary == .avere }!
        let essere = verbs.filter { $0.auxiliary == .essere }
        let ownParticiple = verbs.filter { $0.isIrregular(in: .passatoprossimo) }
        let ownTenses = verbs.compactMap { verb -> (Verb, [Tense])? in
            let tenses = Curriculum.tenseOrder.filter { $0 != .passatoprossimo && verb.isIrregular(in: $0) }
            return tenses.isEmpty ? nil : (verb, tenses)
        }

        // The verbs the caveats are about come first, then more from the start of the path.
        var picks = [model] + regular.filter { $0.spellingNote != nil }
        if let withEssere = regular.first(where: { $0.auxiliary == .essere }) { picks.append(withEssere) }
        for verb in regular where picks.count < maxExamples && !picks.contains(where: { $0.infinitive == verb.infinitive }) {
            picks.append(verb)
        }
        let examples = regular.map(\.infinitive).filter { verb in picks.contains { $0.infinitive == verb } }

        var formation = texts.formation
        if !ownParticiple.isEmpty || !ownTenses.isEmpty {
            formation.append(.init(label: "Ausnahmen:", text: "Manche Verben haben in einzelnen Zeiten eigene Formen (unten aufgeführt). Dort zählen sie im Lernpfad für sich, in den übrigen Zeiten für die Gruppe."))
        }

        var sections: [TenseInfo.Section] = [.init(heading: "Beachten", content: .list(texts.caveats))]
        let notes = verbs.compactMap { verb in verb.spellingNote.map { TenseInfo.ListItem(label: "\(verb.infinitive):", text: $0) } }
        if !notes.isEmpty {
            sections.append(.init(heading: "Schreibung beachten", content: .list(notes)))
        }
        if let first = essere.first {
            sections.append(.init(heading: "Passato prossimo mit essere", content: .paragraph(
                essere.map(\.infinitive).joined(separator: ", ") + " – alle anderen mit avere. Mit essere passt sich das Partizip an: "
                    + "\(first.tableForm(.passatoprossimo, 0)!), \(first.tableForm(.passatoprossimo, 3)!).")))
        } else {
            sections.append(.init(heading: "Passato prossimo mit avere", content: .paragraph(
                "Alle Verben der Gruppe bilden es mit avere: \(model.italian(.passatoprossimo, 0)).")))
        }
        if !ownParticiple.isEmpty {
            sections.append(.init(heading: "Eigenes Partizip", content: .table(
                columns: ["Partizip"], rows: ownParticiple.map { [$0.infinitive, $0.participle] })))
        }
        if !ownTenses.isEmpty {
            sections.append(.init(heading: "Eigene Formen in einzelnen Zeiten", content: .table(
                columns: ["Zeiten"], rows: ownTenses.map { [$0.0.infinitive, $0.1.map(\.shortLabel).joined(separator: ", ")] })))
        }

        let summary = regular.count == verbs.count
            ? "\(verbs.count) Verben, alle in jeder Zeit regelmäßig"
            : "\(verbs.count) Verben, \(regular.count) davon in jeder Zeit regelmäßig"
        return FamilyInfo(summary: summary, formation: formation, examples: examples, sections: sections)
    }

    /// A form split after its stem, to set the ending apart: "parl" + "o", "ho parl" + "ato". Where the
    /// spelling changes the stem, the split comes after what is left of it: "manc" + "herò", "viagg" + "erò".
    static func split(_ form: String, infinitive: String) -> (start: String, ending: String) {
        let stem = infinitive.dropLast(3)
        // In the Passato prossimo the stem is in the participle, after the auxiliary.
        let word = form.split(separator: " ").last ?? Substring(form)
        let kept = zip(word, stem).prefix { $0 == $1 }.count
        let cut = form.index(form.endIndex, offsetBy: kept - word.count)
        return (String(form[..<cut]), String(form[cut...]))
    }
}
