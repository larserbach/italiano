import SwiftUI

struct AuxSettingsView: View {
    @Environment(ProgressStore.self) private var store
    @State private var quizRunning = false

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
                    VerbPicker(selection: $store.aux.verbs, level: store.auxLevel(of:))
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
                     hint: "\(poolSize) mögliche Fragen aus deiner Auswahl.",
                     disabled: poolSize == 0) { quizRunning = true }
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $quizRunning) {
            AuxQuizView(store: store)
        }
    }
}
