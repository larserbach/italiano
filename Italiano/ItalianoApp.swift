import SwiftUI

@main
struct ItalianoApp: App {
    @State private var store: ProgressStore
    @State private var speech: SystemSpeech

    init() {
        let store = ProgressStore()
        _store = State(initialValue: store)
        _speech = State(initialValue: SystemSpeech { [weak store] in store?.readAloud ?? false })
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(\.speech, speech)
                .tint(Theme.gold)
        }
    }
}
