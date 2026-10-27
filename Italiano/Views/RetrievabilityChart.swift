import Charts
import SwiftUI

/// Abruf over time for one group or irregular verb, one line per person, in the statistics. Chips pick the group or
/// verb, the tense (where more than one has answers) and the persons shown; touching the chart reads out the values
/// at that moment.
struct RetrievabilityCard: View {
    /// Every first answer, oldest first; not empty.
    let log: [AnswerLogEntry]
    /// The start of the period chosen above.
    let start: Date
    @Environment(ProgressStore.self) private var store
    @State private var subject: ProgressSubject?

    var body: some View {
        let subjects = Self.subjects(in: log)
        // The group or verb answered last, until another is picked.
        let subject = subject ?? Self.subject(of: log.last!)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Abruf im Verlauf").font(Theme.display(19))
                Text("Wie sicher du die Formen einer Gruppe oder eines unregelmäßigen Verbs gerade weißt, je Person.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if subjects.count > 1 {
                FlowLayout {
                    ForEach(subjects, id: \.self) { option in
                        Button(option.title) { self.subject = option }
                            .buttonStyle(ChipStyle(active: option == subject))
                    }
                }
            }
            // A new subject starts over with its own tenses and persons.
            RetrievabilityChart(subject: subject, entries: log.filter { subject.includes($0.verb, $0.tense) }, start: start)
                .id(subject)
            Text("Jede erste Antwort hebt oder senkt den Abruf, danach sinkt er mit der Zeit – je stabiler, desto langsamer.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private static func subject(of entry: AnswerLogEntry) -> ProgressSubject {
        switch PoolUnit(verb: entry.verb, tense: entry.tense) {
        case .group(let family, _): .family(family)
        case .irregular(let verb, _): .verb(verb)
        }
    }

    /// Groups in path order, then irregular verbs in path order; only those with answers.
    private static func subjects(in log: [AnswerLogEntry]) -> [ProgressSubject] {
        let answered = Set(log.map(subject(of:)))
        return (VerbFamily.regular.map(ProgressSubject.family) + Curriculum.verbOrder.map(ProgressSubject.verb)).filter(answered.contains)
    }
}

/// The lines of one group or verb, with chips for the tense and the persons.
private struct RetrievabilityChart: View {
    let subject: ProgressSubject
    /// The subject's answers, oldest first; not empty.
    let entries: [AnswerLogEntry]
    let start: Date
    @Environment(ProgressStore.self) private var store
    @State private var tense: Tense?
    @State private var persons: Set<Int> = Set(0..<6)
    /// Where the finger is on the chart while it touches it.
    @State private var touch: Date?
    /// The moment read out; it stays after the finger lifts, so the values can be read without it in the way.
    @State private var selection: Date?

    var body: some View {
        // The tense answered last, until another is picked.
        let tense = tense ?? entries.last!.tense
        let tenses = Curriculum.tenseOrder.filter { tense in entries.contains { $0.tense == tense } }
        let now = store.now()
        let curves = RetrievabilityHistory.curves(of: subject.unit(tense), log: entries.filter { $0.tense == tense },
                                                  memory: store.state(of:), until: now)
        let shown = curves.filter { persons.contains($0.person) }
            .map { (person: $0.person, points: RetrievabilityHistory.clipped($0.points, from: start)) }
        let from = max(start, curves.compactMap { $0.points.first?.date }.min() ?? start)

        VStack(alignment: .leading, spacing: 14) {
            if tenses.count > 1 {
                FlowLayout {
                    ForEach(tenses) { option in
                        Button(option.label) {
                            self.tense = option
                            selection = nil
                        }
                        .buttonStyle(ChipStyle(active: option == tense))
                    }
                }
            }
            // The person chips are the legend too: each carries its line's colour.
            FlowLayout {
                ForEach(curves.map(\.person), id: \.self) { person in
                    Button {
                        toggle(person, among: curves.map(\.person))
                    } label: {
                        HStack(spacing: 7) {
                            Capsule().fill(Theme.persons[person]).frame(width: 14, height: 3)
                            Text(Pronoun.italian[person])
                        }
                    }
                    .buttonStyle(ChipStyle(active: persons.contains(person)))
                }
            }
            chart(shown, from: from, to: now)
        }
    }

    private func chart(_ curves: [(person: Int, points: [RetrievabilityHistory.Point])], from start: Date, to end: Date) -> some View {
        let short = MemoryState.days(from: start, to: end) < 2
        return Chart {
            ForEach(curves, id: \.person) { curve in
                ForEach(Array(curve.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Zeit", point.date), y: .value("Abruf", point.value),
                             series: .value("Person", Pronoun.italian[curve.person]))
                        .foregroundStyle(Theme.persons[curve.person])
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let selection {
                RuleMark(x: .value("Zeit", selection))
                    .foregroundStyle(Theme.inkSoft.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        readout(at: selection, curves: curves, short: short)
                    }
            }
        }
        .chartXScale(domain: start...max(end, start + 60))
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let share = value.as(Double.self) { Text(DaysText.percent(share)) }
                }
                .foregroundStyle(Theme.inkSoft)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.line)
                AxisValueLabel(format: short ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .chartXSelection(value: $touch)
        .onChange(of: touch) { if let touch { selection = touch } }
        .environment(\.locale, Locale(identifier: "de_DE"))
        .frame(height: 200)
        .accessibilityLabel("Abruf im Verlauf")
    }

    /// The values at the touched moment: the value first, the person after it.
    private func readout(at date: Date, curves: [(person: Int, points: [RetrievabilityHistory.Point])], short: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date.formatted((short ? Date.FormatStyle().hour().minute() : Date.FormatStyle().day().month(.abbreviated).hour().minute())
                .locale(Locale(identifier: "de_DE"))))
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSoft)
            ForEach(curves, id: \.person) { curve in
                if let value = RetrievabilityHistory.value(at: date, in: curve.points) {
                    HStack(spacing: 6) {
                        Capsule().fill(Theme.persons[curve.person]).frame(width: 10, height: 2)
                        Text(DaysText.percent(value)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        Text(Pronoun.italian[curve.person]).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .padding(8)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
    }

    /// At least one person stays shown.
    private func toggle(_ person: Int, among available: [Int]) {
        if persons.contains(person) {
            if available.contains(where: { $0 != person && persons.contains($0) }) { persons.remove(person) }
        } else {
            persons.insert(person)
        }
    }
}
