import SwiftUI

struct ConjugationSettingsView: View {
    @Environment(ProgressStore.self) private var store
    @State private var sheet: InfoSheet?
    @State private var lessonRunning = false

    private let lengths: [LessonLength] = [.count(5), .count(10), .count(20)]

    var body: some View {
        @Bindable var store = store
        let mode = store.conjugation.mode

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: "Coniugazione",
                             lede: mode == .path
                                 ? "Der Lernpfad wählt die Verben und Zeiten für dich und bringt Neues, sobald du so weit bist."
                                 : "Übe frei mit allem, was schon in deinem Lernpfad ist.")

                Picker("Modus", selection: $store.conjugation.mode) {
                    ForEach(ConjugationMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .path: LearningPathSection()
                case .free: freeSelection
                }

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Lektionslänge")
                    FlowLayout {
                        ForEach(lengths) { length in
                            Button("\(length.label) Aufgaben") { store.conjugation.length = length }
                                .buttonStyle(ChipStyle(active: store.conjugation.length == length))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            StartBar(title: "Lektion starten",
                     disabled: mode == .free && ConjugationLesson.freePool(store).isEmpty) { lessonRunning = true }
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
        .infoSheet($sheet)
        .fullScreenCover(isPresented: $lessonRunning) {
            ConjugationLessonView(store: store)
        }
    }

    @ViewBuilder
    private var freeSelection: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Verben")
            VerbPicker(selection: $store.conjugation.verbs,
                       available: Set(store.unlockedVerbs),
                       level: { store.level(of: $0, tenses: store.conjugation.tenses) },
                       isMistake: { store.isRecentMistake(verb: $0, tenses: store.conjugation.tenses) },
                       preview: .tenseLevels(store.levels(of:)),
                       onDetails: { sheet = .verb($0) })
        }

        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Zeiten")
            FlowLayout {
                ForEach(store.unlockedTenses) { tense in
                    TenseChip(tense: tense,
                              active: store.conjugation.tenses.contains(tense),
                              toggle: { store.conjugation.tenses.toggleKeepingOne(tense) },
                              info: { sheet = .tense(tense) })
                }
            }
            Text("Neue Verben und Zeiten schaltest du im Lernpfad frei.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 4)
        }
    }
}

/// The learning path at a glance: what is closest to bringing something new, and every group and
/// irregular verb in the pool with its progress per tense. A row opens the details.
private struct LearningPathSection: View {
    @Environment(ProgressStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ControlLabel("Als Nächstes")
            nextSteps
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }

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
            Text("Neues kommt, wenn von den letzten \(Curriculum.windowSize) Antworten einer Gruppe oder eines unregelmäßigen Verbs mindestens \(DaysText.percent(Curriculum.goodBar)) gut sind – in späteren Zeiten nur, solange auch die früheren Zeiten so gut laufen. Tippe eine Zeile an für Details.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func status(_ progress: LearningPool.Progress) -> String {
        var parts = ["\(progress.answers) von \(Curriculum.windowSize) Antworten"]
        if let share = progress.share { parts.append("\(DaysText.percent(share)) gut") }
        if !progress.missingPersons.isEmpty, progress.answers >= Curriculum.windowSize / 2 {
            parts.append("mehr nötig: " + progress.missingPersons.map { Pronoun.italian[$0] }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}

/// What long-pressing a verb chip previews.
enum VerbPreview {
    /// The verb's level in every tense.
    case tenseLevels((String) -> [Tense: Int])
    /// Basic facts about the verb (meaning, group, Passato prossimo) and its level.
    case basic

    var isBasic: Bool { if case .basic = self { true } else { false } }

    func tenseLevels(of verb: String) -> [Tense: Int]? {
        if case .tenseLevels(let levels) = self { levels(verb) } else { nil }
    }
}

struct VerbPicker: View {
    @Binding var selection: Set<String>
    /// Limits the picker to these verbs; groups without any are left out.
    var available: Set<String>? = nil
    let level: (String) -> Int
    var isMistake: (String) -> Bool = { _ in false }
    let preview: VerbPreview
    var onDetails: ((String) -> Void)? = nil

    @AppStorage(Tutorial.verbRing.defaultsKey) private var coachSeen = false

    private var groups: [VerbGroupSection] {
        guard let available else { return VerbLibrary.groups }
        return VerbLibrary.groups.compactMap { group in
            let verbs = group.verbs.filter(available.contains)
            return verbs.isEmpty ? nil : VerbGroupSection(label: group.label, verbs: verbs)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !coachSeen {
                CoachMark(text: preview.isBasic ? "Der Ring zeigt das Level des Verbs."
                              : "Der Ring zeigt den Fortschritt der Verbgruppe (in Zeiten, in denen das Verb unregelmäßig ist: des Verbs) in den gewählten Zeiten."
                              + (onDetails == nil ? "" : " Lange drücken für Details."),
                          dismiss: { withAnimation { coachSeen = true } })
                    .transition(.opacity)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    let allSelected = group.verbs.allSatisfy(selection.contains)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(group.label)
                            .font(Theme.display(13, weight: .regular))
                            .foregroundStyle(Theme.gold)
                        Spacer(minLength: 0)
                        Button(allSelected ? "Alle abwählen" : "Alle auswählen") {
                            if allSelected {
                                let rest = selection.subtracting(group.verbs)
                                // At least one verb always stays selected.
                                selection = rest.isEmpty ? Set(group.verbs.prefix(1)) : rest
                            } else {
                                selection.formUnion(group.verbs)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Theme.gold.opacity(0.6), lineWidth: 1))
                        .contentShape(Capsule())
                        .fixedSize()
                    }
                    FlowLayout {
                        ForEach(group.verbs, id: \.self) { verb in
                            let mistake = isMistake(verb)
                            Button {
                                selection.toggleKeepingOne(verb)
                            } label: {
                                HStack(spacing: 7) {
                                    VerbRing(level: level(verb), mistake: mistake)
                                    Text(verb)
                                }
                                .padding(.leading, -6)
                                .padding(.vertical, -2)
                            }
                            .buttonStyle(ChipStyle(active: selection.contains(verb),
                                                   accent: mistake ? Theme.brick : nil))
                            .modifier(VerbPreviewMenu(verb: verb,
                                                      tenseLevels: preview.tenseLevels(of: verb),
                                                      level: level(verb),
                                                      onDetails: onDetails.map { onDetails in
                                { verb in
                                    coachSeen = true
                                    onDetails(verb)
                                }
                            }))
                        }
                    }
                }
            }
        }
    }
}

private struct CoachMark: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Verstanden", action: dismiss)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.gold)
        }
        .padding(12)
        .background(Theme.goldSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.gold))
    }
}

/// Long-press on a verb chip: previews the verb (level per tense, or basic facts), with a link to the verb sheet.
private struct VerbPreviewMenu: ViewModifier {
    let verb: String
    /// The level per tense, or nil for the basic preview.
    let tenseLevels: [Tense: Int]?
    let level: Int
    let onDetails: ((String) -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let onDetails {
                Button("Verb-Details", systemImage: "info.circle") { onDetails(verb) }
            }
        } preview: {
            VStack(alignment: .leading, spacing: 12) {
                if let tenseLevels {
                    Text(verb).font(Theme.display(20))
                    TenseBreakdown(levels: tenseLevels)
                } else {
                    BasicVerbInfo(verb: VerbLibrary.verb(verb), level: level)
                }
            }
            .padding(18)
            .frame(width: 300, alignment: .leading)
            .background(Theme.paper)
            .foregroundStyle(Theme.ink)
        }
    }
}

private struct BasicVerbInfo: View {
    let verb: Verb
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verb.infinitive).font(Theme.display(20))
                Spacer()
                VerbRing(level: level)
            }
            Text("bedeutet auf Deutsch: „\(verb.meaning)“")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
            Text(verb.groupLabel)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
            Text("Passato prossimo: \(verb.italian(.passatoprossimo, 0))")
                .font(.system(size: 14))
                .padding(.top, 4)
        }
    }
}

private struct TenseChip: View {
    let tense: Tense
    let active: Bool
    let toggle: () -> Void
    let info: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                Text(tense.label)
                    .font(.system(size: 14, weight: active ? .medium : .regular))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
            }
            Rectangle().fill(active ? Theme.gold : Theme.line).frame(width: 1)
            Button(action: info) {
                Text("i")
                    .font(Theme.display(13, weight: .regular).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 28)
            }
            .accessibilityLabel("Erklärung zu \(tense.label)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .fixedSize()
        .background(active ? Theme.goldSoft : Theme.paperRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.gold : Theme.line))
    }
}

struct StartBar: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(PrimaryButtonStyle())
            .disabled(disabled)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.paper.opacity(0.96).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
