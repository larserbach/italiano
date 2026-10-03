import SwiftUI

struct SettingsView: View {
    @State private var didReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(title: "Einstellungen", lede: "")

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Tutorials")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Die kleinen Hinweise, die beim ersten Besuch eines Bildschirms erscheinen, wieder anzeigen.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(didReset ? "Zurückgesetzt ✓" : "Tutorials zurücksetzen") {
                            Tutorial.resetAll()
                            didReset = true
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(didReset)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
