import SwiftUI

enum Exercise: Hashable, CaseIterable {
    case conjugation, essereAvere

    var title: String {
        switch self {
        case .conjugation: "Coniugazione"
        case .essereAvere: "Essere o avere?"
        }
    }

    var description: String {
        switch self {
        case .conjugation:
            "Italienische Verben Schritt für Schritt: Der Lernpfad bringt neue Verben und Zeiten, sobald du so weit bist — mit Wiederholungsrunden für Fehler."
        case .essereAvere:
            "Multiple-Choice-Training: Welches Hilfsverb braucht dieses Verb im Passato prossimo — und in welcher Form (ho, sono, ha, è, …)?"
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    ScreenHeader(title: "Italiano", lede: "Wähle eine Übung.")
                    VStack(spacing: 12) {
                        ForEach(Exercise.allCases, id: \.self) { exercise in
                            NavigationLink(value: exercise) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(exercise.title).font(Theme.display(19))
                                    Text(exercise.description)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(Theme.inkSoft)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .topTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Einstellungen")
                .padding(.trailing, 8)
            }
            .screenBackground()
            .navigationTitle("Übungen")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Exercise.self) { exercise in
                switch exercise {
                case .conjugation: ConjugationSettingsView()
                case .essereAvere: AuxSettingsView()
                }
            }
        }
    }
}
