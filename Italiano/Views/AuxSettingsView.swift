import SwiftUI

struct AuxSettingsView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(\.speech) private var speech
    @State private var sheet: InfoSheet?
    @State private var quiz: AuxQuiz?

    private let lengths: [LessonLength] = [.count(10), .count(20), .all]

    var body: some View {
        @Bindable var store = store
        let poolSize = AuxQuiz.pool(verbs: store.aux.verbs).count

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: "Essere o avere?",
                             lede: "Für jedes Verb entscheidest du, welches Hilfsverb das Passato prossimo bildet — und in welcher Form.")

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Verben")
                    VerbPicker(selection: $store.aux.verbs,
                               level: store.auxLevel(of:),
                               onDetails: { sheet = .auxVerb($0) })
                }

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Länge")
                    FlowLayout {
                        ForEach(lengths) { length in
                            Button(length == .all ? length.label : "\(length.label) Fragen") { store.aux.length = length }
                                .buttonStyle(ChipStyle(active: store.aux.length == length))
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            StartBar(title: "Start",
                     disabled: poolSize == 0) { quiz = AuxQuiz(store: store, speech: speech) }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .infoSheet($sheet)
        .fullScreenCover(item: $quiz) { quiz in
            AuxQuizView(quiz: quiz)
        }
    }
}
