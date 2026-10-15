import Foundation

/// One section of the verb picker.
struct VerbGroupSection: Identifiable {
    let label: String
    let verbs: [String]
    var id: String { label }
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
