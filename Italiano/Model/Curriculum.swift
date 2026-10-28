import Foundation

/// The fixed parts of the learning path: orders, thresholds and how a lesson is put together.
enum Curriculum {
    /// The order tenses come into the path. `Tense.allCases` is the display order and differs.
    static let tenseOrder: [Tense] = [.presente, .passatoprossimo, .imperfetto, .futuro, .imperativo, .condizionale, .congiuntivo]

    /// Regular groups take turns, and the most frequent irregular verbs come early.
    static let verbOrder: [String] = [
        "parlare", "abitare", "essere", "lavorare", "avere", "credere", "fare", "dormire", "andare", "capire",
        "guardare", "stare", "arrivare", "potere", "vendere", "volere", "sentire", "dovere", "finire", "venire",
        "tornare", "dire", "viaggiare", "vedere", "partire", "sapere", "preferire", "prendere", "entrare", "mettere",
        "ricevere", "uscire", "camminare", "leggere", "restare", "scrivere", "seguire", "dare", "pulire", "bere",
        "diventare", "conoscere", "guidare", "chiedere", "temere", "rispondere", "ballare", "aprire", "nuotare", "vivere",
        "mancare", "piacere", "passeggiare", "rimanere", "sembrare", "tenere", "sciare", "decidere", "durare", "scegliere",
        "bastare", "cadere",
        "ripetere", "servire", "spedire", "battere", "vestire", "costruire", "cedere", "fuggire", "obbedire",
        "premere", "bollire", "guarire", "correre", "mentire", "suggerire", "scendere", "offrire", "reagire",
        "perdere", "soffrire", "unire", "vincere", "scoprire", "restituire",
    ]

    /// The verbs irregular in this tense, in path order.
    static func irregularVerbs(in tense: Tense) -> [String] {
        verbOrder.filter { VerbLibrary.verb($0).isIrregular(in: tense) }
    }

    /// A unit performs well with this share of Good points in the last `answersKeptPerPerson` answers of each
    /// person …
    static let goodBar = 0.8
    static let answersKeptPerPerson = 4
    /// … and every person answered at least this often among them.
    static let answersPerPerson = 2

    /// Picks `length` questions, favouring what is least known, difficult, freshly added, or in a person ×
    /// tense that lags behind the rest. For a regular group the verb is chosen at random from `verbs`
    /// (different verbs within a lesson where possible). At most 4 questions per unit, unless there are too
    /// few units to fill the lesson.
    static func pickLesson<R: RandomNumberGenerator>(units: [PoolUnit], verbs: (PoolUnit) -> [String], pool: LearningPool,
                                                     memory: LearningMemory, length: Int, at now: Date,
                                                     using rng: inout R) -> [FormKey] {
        let keys = units.flatMap(\.keys)
        guard !keys.isEmpty, length > 0 else { return [] }
        var known: [MemoryKey: Double] = [:]
        for key in keys { known[key] = memory[key]?.retrievability(at: now) ?? 0 }
        let mean = known.values.reduce(0, +) / Double(known.count)
        // A person × tense that lags behind the average is trained more.
        var sums: [PersonTense: (total: Double, count: Int)] = [:]
        for (key, value) in known {
            let sum = sums[PersonTense(key)] ?? (0, 0)
            sums[PersonTense(key)] = (sum.total + value, sum.count + 1)
        }
        let personBoost = sums.mapValues { max(0, mean - $0.total / Double($0.count)) * 1.5 }

        // A weighted shuffle: each key draws u^(1/need²), so the more a key is needed, the likelier it
        // comes early, while every key keeps a chance.
        func ranked() -> [MemoryKey] {
            keys.map { key -> (MemoryKey, Double) in
                // The default difficulty of 5 leaves the need as it is.
                var need = (1 - known[key]!) * (0.7 + 0.06 * (memory[key]?.difficulty ?? 5))
                need += personBoost[PersonTense(key)] ?? 0
                if pool.isFresh(key.unit, at: now) { need += 0.3 }
                return (key, pow(Double.random(in: 0.001..<1, using: &rng), 1 / max(0.01, need * need)))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        }

        let cap = max(4, (length + units.count - 1) / units.count)
        var perUnit: [PoolUnit: Int] = [:]
        var usedVerbs: Set<String> = []
        var picked: [FormKey] = []
        // A regular pattern may come again (with another verb) when there are too few patterns for the lesson.
        // An irregular form has no other verb, so later passes skip it.
        for pass in 0..<4 where picked.count < length {
            for key in ranked() where picked.count < length && perUnit[key.unit, default: 0] < (pass == 0 ? cap : length) {
                let form: FormKey
                switch key {
                case .form(let irregular):
                    guard pass == 0 else { continue }
                    form = irregular
                case .pattern(let pattern):
                    let options = verbs(key.unit).filter {
                        VerbLibrary.verb($0).hasForm(pattern.tense, pattern.person)
                            && !picked.contains(FormKey(verb: $0, tense: pattern.tense, person: pattern.person))
                    }
                    let fresh = options.filter { !usedVerbs.contains($0) }
                    guard let verb = (fresh.isEmpty ? options : fresh).randomElement(using: &rng) else { continue }
                    form = FormKey(verb: verb, tense: pattern.tense, person: pattern.person)
                }
                guard !picked.contains(form) else { continue }
                picked.append(form)
                usedVerbs.insert(form.verb)
                perUnit[key.unit, default: 0] += 1
            }
        }
        return picked
    }
}

/// A person in a tense, across all groups and verbs.
private struct PersonTense: Hashable {
    let tense: Tense
    let person: Int

    init(_ key: MemoryKey) {
        tense = key.tense
        person = key.person
    }
}
