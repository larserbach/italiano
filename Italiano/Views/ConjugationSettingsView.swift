import SwiftUI

struct ConjugationSettingsView: View {
    @Environment(ProgressStore.self) private var store
    @State private var sheet: InfoSheet?
    @State private var lessonRunning = false

    private let lengths: [LessonLength] = [.count(5), .count(10), .count(20)]

    var body: some View {
        @Bindable var store = store
        let poolSize = ConjugationLesson.pool(verbs: store.conjugation.verbs, tenses: store.conjugation.tenses).count

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: "Coniugazione",
                             lede: "Wenige Verben, viele Formen. Stell deine Lektion zusammen, dann geht's los.")

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Verben")
                    VerbPicker(selection: $store.conjugation.verbs,
                               level: store.level(of:),
                               isMistake: { store.lastMistakes.contains($0) })
                }

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Zeiten")
                    FlowLayout {
                        ForEach(Tense.allCases) { tense in
                            TenseChip(tense: tense,
                                      active: store.conjugation.tenses.contains(tense),
                                      toggle: { store.conjugation.tenses.toggleKeepingOne(tense) },
                                      info: { sheet = .tense(tense) })
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Richtung")
                    FlowLayout {
                        ForEach(Direction.allCases) { direction in
                            Button(direction.label) { store.conjugation.direction = direction }
                                .buttonStyle(ChipStyle(active: store.conjugation.direction == direction))
                        }
                    }
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
                     hint: "\(poolSize) mögliche Kombinationen aus deiner Auswahl.",
                     disabled: poolSize == 0) { lessonRunning = true }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .infoSheet($sheet)
        .fullScreenCover(isPresented: $lessonRunning) {
            ConjugationLessonView(store: store)
        }
    }
}

struct VerbPicker: View {
    @Binding var selection: Set<String>
    let level: (String) -> Int
    var isMistake: (String) -> Bool = { _ in false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(VerbCatalog.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.label)
                        .font(Theme.display(13, weight: .regular))
                        .foregroundStyle(Theme.gold)
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
                        }
                    }
                }
            }
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
    let hint: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(disabled)
            Text(hint)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.paper.opacity(0.96).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
