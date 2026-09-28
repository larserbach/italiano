import SwiftUI

struct ConjugationLessonView: View {
    @State private var lesson: ConjugationLesson
    @State private var answer = ""
    @State private var focusToken = 0
    @State private var sheet: InfoSheet?
    @Environment(\.dismiss) private var dismiss

    init(store: ProgressStore) {
        _lesson = State(initialValue: ConjugationLesson(store: store))
    }

    var body: some View {
        Group {
            switch lesson.phase {
            case .question:
                question
            case .roundComplete:
                RoundCompleteView(round: lesson.round, correct: lesson.roundCorrect, total: lesson.roundTotal,
                                  missedCount: lesson.roundMissedCount, noun: ("Aufgabe", "Aufgaben"),
                                  proceed: lesson.startNextRound, quit: { dismiss() })
            case .summary:
                SummaryView(
                    title: "Lektion fertig!",
                    lede: lesson.missedForms.isEmpty
                        ? "Alles auf Anhieb richtig. Ottimo lavoro!"
                        : "Ein paar Formen brauchten mehr als einen Versuch — die stehen unten noch mal.",
                    totalLabel: "Aufgaben", total: lesson.totalPlanned,
                    firstTry: lesson.firstTryCorrect, accuracy: lesson.accuracy,
                    missedTitle: "Diese Formen waren kniffelig", missed: lesson.missedForms,
                    back: { dismiss() },
                    repeatTitle: "Lektion wiederholen", repeatAction: lesson.start)
            }
        }
        .screenBackground()
        .onChange(of: lesson.cardNumber) {
            answer = ""
            focusToken += 1
        }
        .infoSheet($sheet) { focusToken += 1 }
    }

    @ViewBuilder
    private var question: some View {
        if let item = lesson.current {
            let verb = VerbLibrary.verb(item.verb)
            VStack(spacing: 22) {
                LessonTopBar(answered: lesson.roundAnswered, total: lesson.roundTotal) { dismiss() }

                VStack(spacing: 0) {
                    CardMeta(tag: item.tense.label, round: lesson.round) { sheet = .tense(item.tense) }
                        .padding(.bottom, 10)

                    prompt(item: item, verb: verb)

                    VStack(spacing: 8) {
                        HStack(spacing: 0) {
                            PronounLabel(pronoun: item.pronoun, gender: item.gender, marker: item.marker)
                                .padding(.horizontal, 14)
                                .frame(maxHeight: .infinity)
                                .background(Theme.paperRaised)
                                .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
                            AnswerField(text: $answer, isEditable: !lesson.isReviewing,
                                        focusToken: focusToken, onSubmit: submit)
                                .padding(.horizontal, 14)
                        }
                        .frame(height: 48)
                        .background(fieldBackground, in: RoundedRectangle(cornerRadius: 9))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(fieldBorder, lineWidth: 1.5))

                        HStack(spacing: 8) {
                            Button(lesson.isReviewing ? "Verstanden" : "Prüfen", action: submit)
                                .buttonStyle(PrimaryButtonStyle())
                            if !lesson.isReviewing {
                                Button(action: lesson.reveal) {
                                    Text("?").frame(width: 20)
                                }
                                .buttonStyle(GhostButtonStyle(fullWidth: false))
                                .accessibilityLabel("Ich weiß es nicht")
                            }
                        }
                    }

                    feedbackText
                        .font(.system(size: 14))
                        .frame(minHeight: 20)
                        .padding(.top, 10)
                }
                .card()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func prompt(item: ConjugationItem, verb: Verb) -> some View {
        switch item.shown {
        case .german:
            (Text(Pronoun.german(item.person, gender: item.gender) + "  ").fontWeight(.regular).foregroundColor(Theme.inkSoft)
             + Text(verb.german(item.tense, item.person)))
                .font(Theme.display(30, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
        case .italian:
            VStack(spacing: 3) {
                Button { sheet = .verb(verb.infinitive) } label: {
                    Text(verb.infinitive)
                        .font(Theme.display(30, weight: .semibold))
                        .underline(color: Theme.goldSoft)
                }
                .buttonStyle(.plain)
                Text("\(verb.group.rawValue) · \(verb.meaning)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var feedbackText: some View {
        switch lesson.feedback {
        case .none: Text(" ")
        case .correct(let answer): Text("Giusto! \(answer)").foregroundStyle(Theme.olive)
        case .wrong(let answer): Text("Fast — richtig wäre: \(answer)").foregroundStyle(Theme.brick)
        case .wrongGender(let answer):
            Text("Fast — das Partizip passt sich an (\(genderHint)): \(answer)").foregroundStyle(Theme.brick)
        case .revealed(let answer): Text(answer)
        }
    }

    private var fieldBackground: Color {
        switch lesson.feedback {
        case .correct: Theme.oliveBackground
        case .wrong, .wrongGender: Theme.brickBackground
        default: Theme.paper
        }
    }

    private var fieldBorder: Color {
        switch lesson.feedback {
        case .correct: Theme.olive
        case .wrong, .wrongGender: Theme.brick
        default: Theme.gold
        }
    }

    private var genderHint: String {
        guard let item = lesson.current, let gender = item.gender else { return "" }
        return item.marker == nil ? item.pronoun : gender.spokenName
    }

    private func submit() {
        lesson.submit(answer)
    }
}
