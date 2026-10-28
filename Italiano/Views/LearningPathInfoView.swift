import SwiftUI

/// How the learning path in Coniugazione decides what a lesson asks and when something new comes in.
/// Opened from the settings.
struct LearningPathInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(title: "So funktioniert's",
                             lede: "Wie der Lernpfad in Coniugazione die Fragen wählt und wann Neues dazukommt.")
                ForEach(sections) { InfoSection(section: $0) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
            // A readable width on iPad, centred.
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sections: [TenseInfo.Section] {
        let bar = DaysText.percent(Curriculum.goodBar)
        return [
            .init(heading: "Was du lernst", content: .list([
                .init(label: "Gruppen:", text: "Regelmäßige Verben lernst du in Gruppen, jede Zeit für sich: \(VerbFamily.regular.map(\.label).joined(separator: ", ")). Eine Antwort zu parlare im Presente zählt für -are im Presente."),
                .init(label: "Unregelmäßige Verben:", text: "Verben mit eigenen Formen lernst du einzeln – aber nur in den Zeiten, in denen sie unregelmäßig sind. scrivere zählt im Presente für -ere, im Passato prossimo (scritto) für sich."),
                .init(label: "Start:", text: "Der Lernpfad beginnt mit den Verben auf -are und essere im Presente."),
            ])),
            .init(heading: "Wie Antworten zählen", content: .list([
                .init(label: "Gut:", text: "richtig ohne Hilfe – zählt voll."),
                .init(label: "Richtig:", text: "richtig, nachdem du Verb oder Zeit nachgeschaut hast, oder mit einem Akzent oder Buchstaben daneben – zählt halb."),
                .init(label: "Nochmal:", text: "falsch oder mit „?“ aufgedeckt – zählt nicht."),
                .init(label: "Nur der erste Versuch:", text: "Was du in den Wiederholungsrunden einer Lektion beantwortest, zählt nicht mit."),
            ])),
            .init(heading: "Wann Neues dazukommt", content: .list([
                .init(label: "Die Schwelle:", text: "Von den letzten \(Curriculum.windowSize) Antworten einer Gruppe oder eines unregelmäßigen Verbs in einer Zeit sind mindestens \(bar) gut, und jede Person war mindestens \(Curriculum.answersPerPerson)-mal dabei."),
                .init(label: "Am Ende von Runde 1:", text: "Dann prüft die App, was die Schwelle erreicht hat, und schaltet frei, was danach kommt."),
                .init(label: "Frühere Zeiten zuerst:", text: "Eine Gruppe oder ein Verb in einer späteren Zeit schaltet nur frei, solange dieselbe Gruppe bzw. dasselbe Verb auch in allen früheren Zeiten gerade mindestens \(bar) gut ist."),
                .init(label: "Einmal geschafft:", text: "Was die Schwelle erreicht hat, bleibt geschafft (grüner Ring), auch wenn es später wieder schwächer läuft. Es kommt aber weiter in Lektionen vor."),
            ])),
            .init(heading: "Was dazukommt", content: .list([
                .init(label: "Nach einer Gruppe:", text: "die nächste Gruppe in derselben Zeit und dieselbe Gruppe in der nächsten Zeit."),
                .init(label: "Nach einem unregelmäßigen Verb:", text: "das nächste Verb, das in derselben Zeit zum ersten Mal unregelmäßig ist, und dasselbe Verb in seiner nächsten unregelmäßigen Zeit – sobald eine Gruppe diese Zeit schon hat."),
                .init(label: "Reihenfolge der Gruppen:", text: VerbFamily.regular.map(\.label).joined(separator: " → ") + "."),
                .init(label: "Reihenfolge der Zeiten:", text: Curriculum.tenseOrder.map(\.label).joined(separator: " → ") + "."),
                .init(label: "Neue Verben:", text: "Eine Gruppe fragt in späteren Zeiten nur Verben ab, die du schon im Presente hattest: venivo wartet, bis venire im Presente dran war."),
            ])),
            .init(heading: "Welche Fragen eine Lektion stellt", content: .list([
                .init(label: "Gedächtnis:", text: "Für jede Person einer Gruppe und jede Form eines unregelmäßigen Verbs merkt sich die App den Abruf (wie sicher du sie jetzt weißt), die Stabilität (Tage, bis der Abruf auf die Hälfte fällt) und die Schwierigkeit (1–10)."),
                .init(label: "Auswahl:", text: "Häufiger kommt, was du gerade am wenigsten sicher weißt, was dir schwerfällt und was in den letzten 24 Stunden dazugekommen ist – und Personen, die hinter den anderen zurückliegen."),
                .init(label: "Mischung:", text: "Meist höchstens 4 Fragen pro Gruppe oder Verb. Bei einer Gruppe wird das Verb zufällig gewählt, möglichst jedes Mal ein anderes."),
            ])),
            .init(heading: "Wo du es siehst", content: .list([
                .init(label: "Coniugazione:", text: "Die Ringe zeigen, wie nah eine Gruppe oder ein Verb an der Schwelle ist. „Als Nächstes“ zeigt, was am nächsten dran ist und was es bringt."),
                .init(label: "Details:", text: "Tippe dort eine Gruppe oder ein Verb an: Du siehst je Zeit den Stand, die Werte je Person und jede Antwort mit ihrer Bewertung."),
            ])),
        ]
    }
}
