import SwiftUI

@main
struct ItalianoApp: App {
    @State private var store = ProgressStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .tint(Theme.gold)
        }
    }
}
