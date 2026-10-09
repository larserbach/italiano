import Foundation

/// How a typed answer compares to the expected form.
enum AnswerCheck: Equatable {
    case right
    /// Only an accent or one letter off, and not a form the learner might have meant instead.
    case almost
    /// Right form, but for the other gender.
    case wrongGender
    case wrong

    /// One letter may be off only in answers at least this long; in short ones (fa, so, ho) it changes too much.
    static let typoMinLength = 4

    init(_ guess: String, for item: ConjugationItem) {
        let typed = normalize(guess)
        let accepted = item.accepted.map(normalize)
        if typed.isEmpty {
            self = .wrong
        } else if accepted.contains(typed) {
            self = .right
        } else if item.otherGenderAnswer.map(normalize) == typed {
            self = .wrongGender
        } else if Self.isSlip(typed, of: accepted, item: item) {
            self = .almost
        } else {
            self = .wrong
        }
    }

    private static func isSlip(_ typed: String, of accepted: [String], item: ConjugationItem) -> Bool {
        let folded = fold(typed)
        let close = accepted.map(fold).contains { answer in
            folded == answer || (answer.count >= typoMinLength && isOneEditApart(folded, answer))
        }
        guard close else { return false }
        // Another real form of the verb (parli for parlo, parlerà for parlerò) is a real mistake …
        let verb = VerbLibrary.verb(item.verb)
        let answers = Set(accepted.map(fold))
        if otherForms(of: verb).contains(where: { $0 == folded && !answers.contains($0) }) { return false }
        // … and so is the spelling trap the app teaches (pagerò for pagherò, viaggierò for viaggerò).
        if let trap = trap(verb, item.tense, item.person), !answers.contains(fold(trap)), fold(trap) == folded { return false }
        return true
    }

    /// Every form of the verb in every tense, person and gender, accents removed.
    private static func otherForms(of verb: Verb) -> Set<String> {
        var forms: Set<String> = []
        for tense in Tense.allCases {
            for person in tense.persons where verb.hasForm(tense, person) {
                for gender in Gender.allCases {
                    verb.acceptedAnswers(tense, person, gender: gender).forEach { forms.insert(fold(normalize($0))) }
                }
            }
        }
        return forms
    }

    /// The form without the spelling rules, where they change it.
    private static func trap(_ verb: Verb, _ tense: Tense, _ person: Int) -> String? {
        guard !verb.isIrregular(in: tense) else { return nil }
        let plain = Conjugator.regularForms(infinitive: verb.infinitive, group: verb.group, spellingRules: false)[tense]?[person] ?? nil
        return plain.map(normalize)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
    }

    /// One letter replaced, added, removed, or two neighbours swapped.
    static func isOneEditApart(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        guard a != b, abs(a.count - b.count) <= 1 else { return false }
        let prefix = zip(a, b).prefix { $0 == $1 }.count
        let restA = a[prefix...], restB = b[prefix...]
        if a.count == b.count {
            if restA.dropFirst() == restB.dropFirst() { return true }
            return restA.count >= 2 && restA.first == restB.dropFirst().first && restB.first == restA.dropFirst().first
                && restA.dropFirst(2) == restB.dropFirst(2)
        }
        return a.count > b.count ? restA.dropFirst() == restB : restA == restB.dropFirst()
    }
}
