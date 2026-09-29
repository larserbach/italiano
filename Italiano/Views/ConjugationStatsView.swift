import Charts
import SwiftUI

/// Correct answers vs. mistakes per tense over time, with a breakdown by verb type.
struct ConjugationStatsView: View {
    let history: AnswerHistory
    @AppStorage("stats-range") private var range: StatsRange = .days14

    var body: some View {
        let window = history.window(for: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Statistik", lede: caption)

                if history.isEmpty {
                    Text("Noch keine Statistik — starte eine Lektion.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                        .card()
                } else {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let totals = history.totals(in: window, tense: nil)
                    HStack(spacing: 10) {
                        StatTile(value: "\(totals.total)", label: "Antworten")
                        StatTile(value: "\(totals.mistakes)", label: "Fehler")
                        StatTile(value: totals.accuracy.map { "\($0)%" } ?? "–", label: "Trefferquote")
                    }

                    ForEach(Tense.allCases) { tense in
                        TenseStatsCard(history: history, window: window, tense: tense)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var caption: String {
        guard let first = history.firstDay else { return "Richtige Antworten und Fehler je Zeit." }
        return "Erste Antworten je Karte, seit \(first.formatted(.dateTime.day().month(.wide).year()))."
    }
}

private struct TenseStatsCard: View {
    let history: AnswerHistory
    let window: StatsWindow
    let tense: Tense
    @State private var selectedDate: Date?

    var body: some View {
        let totals = history.totals(in: window, tense: tense)
        if totals.total == 0 {
            HStack {
                Text(tense.label).font(Theme.display(17))
                Spacer()
                Text("noch keine Antworten")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
            }
            .card()
        } else {
            let buckets = history.buckets(in: window, tense: tense)
            let groups = history.byGroup(in: window, tense: tense)
            let top = history.topMistakes(in: window, tense: tense)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tense.label).font(Theme.display(19))
                    Text(summary(for: selectedBucket(in: buckets), totals: totals))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                }

                chart(buckets)

                if groups.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        ControlLabel("Nach Verbtyp")
                        ForEach(groups) { group in
                            GroupRow(group: group, maxTotal: groups.map(\.counts.total).max() ?? 1)
                        }
                    }
                }

                if !top.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ControlLabel("Häufigste Fehler")
                        ForEach(top) { entry in
                            HStack {
                                Text(entry.verb)
                                Spacer()
                                Text("\(entry.counts.mistakes) von \(entry.counts.total)")
                                    .foregroundStyle(Theme.inkSoft)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 14))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func chart(_ buckets: [StatsBucket]) -> some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Zeitraum", bucket.start, unit: window.unit),
                        y: .value("Antworten", bucket.counts.correct))
                    .foregroundStyle(by: .value("Art", "Richtig"))
                BarMark(x: .value("Zeitraum", bucket.start, unit: window.unit),
                        y: .value("Antworten", bucket.counts.mistakes))
                    .foregroundStyle(by: .value("Art", "Fehler"))
            }
            if let selected = selectedBucket(in: buckets) {
                RuleMark(x: .value("Zeitraum", selected.start, unit: window.unit))
                    .foregroundStyle(Theme.line.opacity(0.6))
            }
        }
        .chartForegroundStyleScale(domain: ["Richtig", "Fehler"], range: [Theme.olive, Theme.brick])
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: axisFormat)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel().foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(height: 150)
    }

    private var axisFormat: Date.FormatStyle {
        switch window.unit {
        case .month: .dateTime.month(.abbreviated)
        default: .dateTime.day().month(.abbreviated)
        }
    }

    private func selectedBucket(in buckets: [StatsBucket]) -> StatsBucket? {
        guard let selectedDate else { return nil }
        return buckets.last { $0.start <= selectedDate }
    }

    private func summary(for bucket: StatsBucket?, totals: AnswerCounts) -> String {
        let counts = bucket?.counts ?? totals
        var text = "\(counts.correct) richtig · \(counts.mistakes) Fehler"
        if let accuracy = counts.accuracy { text += " · \(accuracy) %" }
        guard let bucket else { return text }
        return "\(bucketLabel(bucket.start)): \(text)"
    }

    private func bucketLabel(_ date: Date) -> String {
        switch window.unit {
        case .month: date.formatted(.dateTime.month(.wide).year())
        case .weekOfYear: "Woche ab \(date.formatted(.dateTime.day().month(.abbreviated)))"
        default: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}

/// A verb group's correct answers and mistakes as one thin stacked bar, scaled to the largest group.
private struct GroupRow: View {
    let group: GroupStats
    let maxTotal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.label).font(.system(size: 13))
                Spacer()
                Text("\(group.counts.correct) richtig · \(group.counts.mistakes) Fehler")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                let scale = geo.size.width / CGFloat(max(maxTotal, 1))
                HStack(spacing: 2) {
                    if group.counts.correct > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.olive)
                            .frame(width: CGFloat(group.counts.correct) * scale)
                    }
                    if group.counts.mistakes > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.brick)
                            .frame(width: CGFloat(group.counts.mistakes) * scale)
                    }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}
