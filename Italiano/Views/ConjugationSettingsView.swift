import SwiftUI

struct ConjugationSettingsView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(\.speech) private var speech
    @State private var lesson: ConjugationLesson?

    private let lengths: [LessonLength] = [.count(5), .count(10), .count(20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: "Coniugazione",
                             lede: "Der Lernpfad wählt die Verben und Zeiten für dich und bringt Neues, sobald du so weit bist.")

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Lektionslänge")
                    FlowLayout {
                        ForEach(lengths) { length in
                            Button("\(length.label) Aufgaben") { store.conjugation.length = length }
                                .buttonStyle(ChipStyle(active: store.conjugation.length == length))
                        }
                    }
                }

                LearningPathSection()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            StartBar(title: "Lektion starten", disabled: false) {
                lesson = ConjugationLesson(store: store, speech: speech)
            }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ConjugationStatsView(history: store.history)
                } label: {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel("Statistik")
            }
        }
        .fullScreenCover(item: $lesson) { lesson in
            ConjugationLessonView(lesson: lesson)
        }
    }
}

/// The learning path at a glance: every group and irregular verb in the pool with its progress per
/// tense, and what is closest to bringing something new. A row opens the details.
private struct LearningPathSection: View {
    @Environment(ProgressStore.self) private var store

    var body: some View {
        // Every group in the pool in at least one tense; the same for irregular verbs below.
        let families = VerbFamily.regular.filter { family in store.pool.units.contains { $0 == .group(family, $0.tense) } }
        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Verbgruppen")
            VStack(spacing: 0) {
                ForEach(families, id: \.self) { family in
                    row(.family(family), detail: "\(family.verbs.count) Verben")
                }
            }
        }

        let irregular = Curriculum.verbOrder.filter { verb in store.pool.units.contains { $0 == .irregular(verb, $0.tense) } }
        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Unregelmäßige Verben")
            VStack(spacing: 0) {
                ForEach(irregular, id: \.self) { verb in
                    row(.verb(verb), detail: VerbLibrary.verb(verb).meaning)
                }
            }
        }

        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Als Nächstes")
            nextSteps
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    private func row(_ subject: ProgressSubject, detail: String) -> some View {
        NavigationLink {
            UnitProgressView(subject: subject)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(subject.title).font(Theme.display(17))
                        Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.inkSoft)
                    }
                    FlowLayout {
                        ForEach(subject.tenses.map(subject.unit).filter(store.pool.contains), id: \.self) { unit in
                            HStack(spacing: 5) {
                                ProgressRing(progress: store.progress(of: unit))
                                Text(unit.tense.shortLabel)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.trailing, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    /// The three units closest to performing well, with what they would bring.
    @ViewBuilder
    private var nextSteps: some View {
        let open = store.pool.units
            .filter { !store.progress(of: $0).passed && !store.pool.unlocks(of: $0).filter { !store.pool.contains($0) }.isEmpty }
            .sorted { store.progress(of: $0).fraction > store.progress(of: $1).fraction }
            .prefix(3)
        VStack(alignment: .leading, spacing: 12) {
            if open.isEmpty {
                Text("Alles im Pool läuft schon – übe weiter, um es zu festigen.")
            }
            ForEach(Array(open), id: \.self) { unit in
                let progress = store.progress(of: unit)
                let brings = store.pool.unlocks(of: unit).filter { !store.pool.contains($0) }
                HStack(alignment: .top, spacing: 10) {
                    ProgressRing(progress: progress)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("**\(unit.label)**")
                        Text(status(progress))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                        let blockers = store.pool.blockers(of: unit)
                        if !blockers.isEmpty {
                            Text("Wartet auf: " + blockers.map { "\($0.label) (\(store.progress(of: $0).share.map(DaysText.percent) ?? "–"))" }
                                .joined(separator: ", "))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.brick)
                        }
                        Text("Bringt: " + brings.map(\.label).joined(separator: ", "))
                            .font(.system(size: 13))
                    }
                }
            }
            Text("Neues kommt, wenn von den letzten \(Curriculum.answersKeptPerPerson) Antworten je Person einer Gruppe oder eines unregelmäßigen Verbs mindestens \(DaysText.percent(Curriculum.goodBar)) gut sind – in späteren Zeiten nur, solange auch die früheren Zeiten so gut laufen. Tippe eine Zeile an für Details.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func status(_ progress: LearningPool.Progress) -> String {
        var parts = ["\(progress.counted) von \(progress.needed) Antworten"]
        if let share = progress.share { parts.append("\(DaysText.percent(share)) gut") }
        // Only once half the needed answers are there: before that most persons are missing anyway.
        if !progress.missingPersons.isEmpty, progress.counted >= progress.needed / 2 {
            parts.append("mehr nötig: " + progress.missingPersons.map { Pronoun.italian[$0] }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}
