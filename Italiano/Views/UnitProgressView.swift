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

/// A regular group or a verb in the tenses it is irregular in: what the progress rings are about.
enum ProgressSubject: Hashable {
    case family(VerbFamily)
    case verb(String)

    func unit(_ tense: Tense) -> PoolUnit {
        switch self {
        case .family(let family): .group(family, tense)
        case .verb(let verb): .irregular(verb, tense)
        }
    }

    /// Tenses it can be practised in, in path order.
    var tenses: [Tense] {
        switch self {
        case .family: Curriculum.tenseOrder
        case .verb(let verb): Curriculum.tenseOrder.filter(VerbLibrary.verb(verb).isIrregular)
        }
    }

    var title: String {
        switch self {
        case .family(let family): family.label
        case .verb(let verb): verb
        }
    }

    /// Whether an answer on this verb in this tense counts here.
    func includes(_ verb: String, _ tense: Tense) -> Bool {
        PoolUnit(verb: verb, tense: tense) == unit(tense)
    }
}

/// Everything the app knows about a regular group or an irregular verb: per tense the progress toward
/// performing well, what that unlocks, the memory per person, and every answer with its rating.
/// Meant to make the learning path's decisions traceable.
struct UnitProgressView: View {
    let subject: ProgressSubject
    @Environment(ProgressStore.self) private var store
    @State private var sheet: InfoSheet?

    var body: some View {
        // Retrievability falls by the minute, so the screen refreshes itself.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenHeader(title: subject.title, lede: lede)
                    if case .verb(let verb) = subject {
                        Button("Konjugation ansehen") { sheet = .verb(verb) }
                            .buttonStyle(GhostButtonStyle(fullWidth: false))
                    }
                    explanation

                    VStack(alignment: .leading, spacing: 10) {
                        ControlLabel("Zeiten")
                        ForEach(subject.tenses) { tense in
                            UnitCard(unit: subject.unit(tense))
                        }
                    }

                    AnswerLogList(entries: store.log.entries.filter { subject.includes($0.verb, $0.tense) })
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

    private var lede: String {
        switch subject {
        case .family(let family):
            let verbs = family.verbs
            return "\(verbs.count) Verben: " + verbs.prefix(6).joined(separator: ", ") + (verbs.count > 6 ? ", …" : "")
        case .verb(let verb):
            return "„\(VerbLibrary.verb(verb).meaning)“ · \(VerbLibrary.verb(verb).groupLabel)"
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("So funktioniert's").font(.system(size: 14, weight: .semibold))
            Text("""
                Regelmäßige Formen zählen für ihre Gruppe, unregelmäßige für das Verb allein – je Zeit: \
                scrivere zählt im Presente für -ere, im Passato prossimo (scritto) für sich. Jede erste Antwort \
                ist **Gut** (ohne Hilfe), **Richtig** (Verb oder Zeit nachgeschaut, zählt halb) oder **Nochmal** \
                (falsch oder „?“). Sind von den letzten \(Curriculum.windowSize) Antworten mindestens \
                \(DaysText.percent(Curriculum.goodBar)) gut und jede Person mindestens \(Curriculum.answersPerPerson)-mal \
                dabei, kommt Neues dazu – in einer späteren Zeit nur, wenn auch alle früheren Zeiten gerade so \
                gut laufen.
                Je Person: **Abruf** (wie sicher jetzt), **Stabilität** (Tage, bis der Abruf auf die Hälfte \
                fällt), **Schwierigkeit** (1–10). Daraus wählt die Lektion die Fragen.
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

private struct UnitCard: View {
    let unit: PoolUnit
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let inPool = store.pool.contains(unit)
        let progress = store.progress(of: unit)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if inPool { ProgressRing(progress: progress) }
                Text(unit.tense.label).font(.system(size: 15, weight: .medium))
                Spacer()
                Text(!inPool ? "noch nicht im Pool" : progress.passed ? "geschafft" : "läuft")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(!inPool ? Theme.inkSoft : progress.passed ? Theme.olive : Theme.gold)
            }
            if inPool {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Antworten", "\(progress.answers) von \(Curriculum.windowSize)")
                    row("Davon gut", progress.share.map { "\(DaysText.percent($0)) (nötig \(DaysText.percent(Curriculum.goodBar)))" } ?? "–")
                    row("Zu wenig geübt", progress.missingPersons.isEmpty ? "–" : progress.missingPersons.map { Pronoun.italian[$0] }.joined(separator: ", "))
                }
                .font(.system(size: 13.5))
                let unlocks = store.pool.unlocks(of: unit).filter { !store.pool.contains($0) }
                if !progress.passed, !unlocks.isEmpty {
                    Text("Bringt: " + unlocks.map(\.label).joined(separator: ", "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkSoft)
                    let blockers = store.pool.blockers(of: unit)
                    if !blockers.isEmpty {
                        Text("Wartet, bis wieder \(DaysText.percent(Curriculum.goodBar)) gut: "
                             + blockers.map { "\($0.tense.label) (\(store.progress(of: $0).share.map(DaysText.percent) ?? "–"))" }.joined(separator: ", "))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.brick)
                    }
                }
                PersonTable(unit: unit)
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
}

/// Per person: what is measured for picking (the group pattern, or the irregular form).
private struct PersonTable: View {
    let unit: PoolUnit
    @Environment(ProgressStore.self) private var store

    var body: some View {
        let now = store.now()
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Text("Person")
                Text("Abruf")
                Text("Stabilität")
                Text("Schw.")
                Text("Zuletzt")
            }
            .foregroundStyle(Theme.inkSoft)
            ForEach(unit.keys, id: \.person) { key in
                let state = store.state(of: key)
                GridRow {
                    Text(Pronoun.italian[key.person])
                    Text(state.map { DaysText.percent($0.retrievability(at: now)) } ?? "–")
                    Text(state.map { DaysText.of($0.stability) } ?? "–")
                    Text(state.map { DaysText.number($0.difficulty) } ?? "–")
                    Text(state?.lastRating.label ?? "–").foregroundStyle(state?.lastRating.color ?? Theme.inkSoft)
                }
            }
        }
        .font(.system(size: 12.5))
        .monospacedDigit()
        .padding(.top, 4)
    }
}

/// Every first answer, newest first, grouped by day.
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
