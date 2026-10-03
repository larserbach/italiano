import SwiftUI

struct SettingsView: View {
    @Environment(ProgressStore.self) private var store
    @State private var didReset = false
    @State private var didResetProgress = false
    @State private var confirmingProgressReset = false

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

                VStack(alignment: .leading, spacing: 7) {
                    ControlLabel("Fortschritt")
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Alle Level, den Lernpfad, die Statistik und die markierten Fehler auf null setzen. Die Lektionslängen bleiben erhalten.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(didResetProgress ? "Zurückgesetzt ✓" : "Fortschritt zurücksetzen") {
                            confirmingProgressReset = true
                        }
                        .buttonStyle(GhostButtonStyle(destructive: !didResetProgress))
                        .disabled(didResetProgress)
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
        .alert("Fortschritt zurücksetzen?", isPresented: $confirmingProgressReset) {
            Button("Abbrechen", role: .cancel) {}
            Button("Zurücksetzen", role: .destructive) {
                store.resetProgress()
                didResetProgress = true
            }
        } message: {
            Text("""
                Das passiert:
                • Alle Level in Coniugazione und Essere o avere? springen auf 0.
                • Der Lernpfad beginnt wieder mit parlare im Presente.
                • Die Statistik wird gelöscht.
                • Die rot markierten Fehler der letzten Lektion verschwinden.

                Das lässt sich nicht rückgängig machen. Die Lektionslängen und die Verbauswahl bei Essere o avere? bleiben wie sie sind.
                """)
        }
    }
}
