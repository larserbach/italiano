import SwiftUI

/// Days in German notation: "2,4 Tage".
enum DaysText {
    static func number(_ days: Double) -> String {
        days.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE")))
    }

    static func of(_ days: Double) -> String { "\(number(days)) Tage" }

    /// After "ab": "ab 1,2 Tagen".
    static func dative(_ days: Double) -> String { "\(number(days)) Tagen" }

    /// A share as "71 %", with a space that does not break.
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))\u{00A0}%" }
}

/// Everything the app knows about one verb: per tense the verb×tense memory behind the ring, each
/// person's form and the group pattern, the verb's place in the pool, and every answer with its rating.
/// Meant to make the learning path's decisions traceable.
struct VerbProgressView: View {
    let verb: String
    @Environment(ProgressStore.self) private var store
    @State private var sheet: InfoSheet?

    var body: some View {
        // Retrievability falls by the minute, so the screen refreshes itself.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenHeader(title: verb, lede: "„\(VerbLibrary.verb(verb).meaning)“ · \(VerbFamily(verb: verb).label)")
                    Button("Konjugation ansehen") { sheet = .verb(verb) }
                        .buttonStyle(GhostButtonStyle(fullWidth: false))
                    explanation

                    VStack(alignment: .leading, spacing: 10) {
                        ControlLabel("Zeiten")
                        ForEach(Curriculum.tenseOrder.filter(VerbLibrary.verb(verb).hasTense)) { tense in
                            TenseProgressCard(verb: verb, tense: tense)
                        }
                    }

                    AnswerLogList(entries: store.log.entries(for: verb))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .infoSheet($sheet)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("So funktioniert's").font(.system(size: 14, weight: .semibold))
            Text("""
                Jede erste Antwort wird bewertet: **Gut** (richtig ohne Hilfe), **Richtig** (richtig, aber Verb \
                oder Zeit nachgeschaut) oder **Nochmal** (falsch oder „?“). Gespeichert wird das für die Form, \
                für Verb + Zeit und – bei regelmäßigen Verben – für das Muster der Gruppe.
                **Stabilität**: Tage, bis der Abruf auf die Hälfte fällt. **Abruf**: wie sicher du es jetzt \
                weißt. **Schwierigkeit**: 1–10. Gut erhöht Stabilität und Abruf, Nochmal senkt beides, \
                Richtig ändert nichts.
                """)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private extension Rating {
    var label: String {
        switch self {
        case .again: "Nochmal"
        case .correct: "Richtig"
        case .good: "Gut"
        }
    }

    var color: Color {
        switch self {
        case .again: Theme.brick
        case .correct: Theme.gold
        case .good: Theme.olive
        }
    }
}

private struct TenseProgressCard: View {
    let verb: String
    let tense: Tense
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let cell = Cell(verb: verb, tense: tense)
        let inPool = store.isUnlocked(verb: verb, tense: tense)
        let now = store.now()

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VerbRing(level: store.level(of: verb, tense: tense))
                Text(tense.label).font(.system(size: 15, weight: .medium))
                Spacer()
                Text(status(inPool: inPool, cell: cell))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(inPool ? Theme.gold : Theme.inkSoft)
            }
            if let state = store.state(of: cell) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Stabilität", DaysText.of(state.stability))
                    row("Abruf jetzt", DaysText.percent(state.retrievability(at: now)))
                    row("Schwierigkeit", DaysText.number(state.difficulty))
                    row("Zuletzt", "\(state.lastRating.label) · \(relative(state.last))")
                    row("Antworten", state.answers == 0 ? "– (übernommen)" : "\(state.answers) · \(state.good) gut")
                }
                .font(.system(size: 13.5))
                PersonTable(verb: verb, tense: tense)
            } else if inPool {
                Text("Noch nicht geübt.").font(.system(size: 13.5)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .opacity(inPool ? 1 : 0.55)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Theme.inkSoft)
            Text(value).fontWeight(.medium)
        }
    }

    private func status(inPool: Bool, cell: Cell) -> String {
        if inPool { return "im Pool" }
        return store.readiness?.next == cell ? "kommt als Nächstes" : "noch nicht im Pool"
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: store.now())
    }
}

/// Per person: the form's own memory, and for regular verbs the group pattern it shares.
private struct PersonTable: View {
    let verb: String
    let tense: Tense
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let now = store.now()
        let regular = VerbFamily(verb: verb) != .irregular
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("Person")
                Text("Abruf")
                Text("Stab.")
                Text("Schw.")
                if regular { Text("Gruppe") }
            }
            .foregroundStyle(Theme.inkSoft)
            ForEach(Curriculum.forms(Cell(verb: verb, tense: tense)), id: \.person) { form in
                let state = store.state(of: form)
                GridRow {
                    Text(Pronoun.italian[form.person])
                    Text(state.map { DaysText.percent($0.retrievability(at: now)) } ?? "–")
                        .foregroundStyle(state?.lastRating.color ?? Theme.inkSoft)
                    Text(state.map { DaysText.number($0.stability) } ?? "–")
                    Text(state.map { DaysText.number($0.difficulty) } ?? "–")
                    if regular {
                        Text(store.patternState(of: form).map { DaysText.percent($0.retrievability(at: now)) } ?? "–")
                    }
                }
            }
        }
        .font(.system(size: 12.5))
        .monospacedDigit()
        .padding(.top, 4)
    }
}

/// Every first answer for the verb, newest first, grouped by day.
private struct AnswerLogList: View {
    let entries: [AnswerLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Antworten (\(entries.count))")
            if entries.isEmpty {
                Text("Noch keine Antworten.").font(.system(size: 13.5)).foregroundStyle(Theme.inkSoft)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.day) { group in
                    Text(dayLabel(group.day))
                        .font(Theme.display(13, weight: .regular))
                        .foregroundStyle(Theme.gold)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    ForEach(group.entries) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
        }
    }

    private var days: [(day: Date, entries: [AnswerLogEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries.reversed()) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Heute" }
        if Calendar.current.isDateInYesterday(day) { return "Gestern" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))
    }
}

private struct EntryRow: View {
    let entry: AnswerLogEntry

    var body: some View {
        let verb = VerbLibrary.verb(entry.verb)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSoft)
                Text("\(Pronoun.italian(entry.person, gender: entry.gender)) \(verb.italian(entry.tense, entry.person, gender: entry.gender))")
                    .fontWeight(.medium)
                Text(entry.tense.shortLabel).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(entry.rating.label)
                    .fontWeight(.medium)
                    .foregroundStyle(entry.rating.color)
            }
            .font(.system(size: 14))
            Text(details)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var details: String {
        guard let before = entry.stabilityBefore else {
            return "Erste Antwort · Stabilität \(DaysText.of(entry.stabilityAfter))"
        }
        return "Abruf vorher \(DaysText.percent(entry.retrievabilityBefore)) · Stabilität \(DaysText.number(before)) → \(DaysText.of(entry.stabilityAfter))"
    }
}
