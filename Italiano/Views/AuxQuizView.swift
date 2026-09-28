import SwiftUI

struct AuxQuizView: View {
    @State private var quiz: AuxQuiz
    @State private var sheet: InfoSheet?
    @Environment(\.dismiss) private var dismiss

    init(store: ProgressStore) {
        _quiz = State(initialValue: AuxQuiz(store: store))
    }

    var body: some View {
        Group {
            switch quiz.phase {
            case .question:
                question
            case .roundComplete:
                RoundCompleteView(round: quiz.round, correct: quiz.roundCorrect, total: quiz.roundTotal,
                                  missedCount: quiz.roundMissedCount, noun: ("Frage", "Fragen"),
                                  proceed: quiz.startNextRound, quit: { dismiss() })
            case .summary:
                SummaryView(
                    title: "Fertig!",
                    lede: quiz.missedForms.isEmpty
                        ? "Alles auf Anhieb richtig. Perfetto!"
                        : "Ein paar Verben brauchten mehr als einen Versuch — die stehen unten noch mal.",
                    totalLabel: "Fragen", total: quiz.totalPlanned,
                    firstTry: quiz.firstTryCorrect, accuracy: quiz.accuracy,
                    missedTitle: "Diese Verben waren kniffelig", missed: quiz.missedForms,
                    back: { dismiss() },
                    repeatTitle: "Nochmal", repeatAction: quiz.start)
            }
        }
        .screenBackground()
        .infoSheet($sheet)
    }

    @ViewBuilder
    private var question: some View {
        if let item = quiz.current {
            VStack(spacing: 22) {
                LessonTopBar(answered: quiz.roundAnswered, total: quiz.roundTotal) { dismiss() }

                VStack(spacing: 0) {
                    CardMeta(tag: "Passato prossimo", round: quiz.round)
                        .padding(.bottom, 10)

                    Button { sheet = .verb(item.verb) } label: {
                        Text(item.verb)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSoft)
                            .underline(color: Theme.goldSoft)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(Pronoun.italian[item.person])
                        Rectangle().fill(Theme.inkSoft).frame(width: 44, height: 2)
                        Text(VerbLibrary.verb(item.verb).participle)
                    }
                    .font(Theme.display(30, weight: .semibold))
                    .padding(.bottom, 16)

                    VStack(spacing: 10) {
                        ForEach(item.options, id: \.self) { option in
                            Button { quiz.choose(option) } label: {
                                Text(option)
                                    .font(Theme.display(20))
                                    .frame(maxWidth: .infinity)
                                    .padding(14)
                                    .background(optionBackground(option, item: item), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(optionBorder(option, item: item), lineWidth: 1.5))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Group {
                        if quiz.isAnswered && !quiz.answeredWrong {
                            Text("Giusto! \(item.fullForm)").foregroundStyle(Theme.olive)
                        } else if quiz.answeredWrong {
                            Text("Richtig: \(item.fullForm)").foregroundStyle(Theme.brick)
                        } else {
                            Text(" ")
                        }
                    }
                    .font(.system(size: 14))
                    .padding(.top, 10)

                    if quiz.answeredWrong {
                        Button("Weiter", action: quiz.next)
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, 8)
                    }
                }
                .card()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    private func optionBackground(_ option: String, item: AuxItem) -> Color {
        guard quiz.isAnswered else { return Theme.paper }
        if option == item.correctForm { return Theme.oliveBackground }
        if option == quiz.chosen { return Theme.brickBackground }
        return Theme.paper
    }

    private func optionBorder(_ option: String, item: AuxItem) -> Color {
        guard quiz.isAnswered else { return Theme.line }
        if option == item.correctForm { return Theme.olive }
        if option == quiz.chosen { return Theme.brick }
        return Theme.line
    }
}
