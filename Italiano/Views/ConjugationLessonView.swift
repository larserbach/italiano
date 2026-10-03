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
                RoundCompleteView(round: lesson.rounds.round, correct: lesson.rounds.roundCorrect, total: lesson.rounds.roundTotal,
                                  missedCount: lesson.rounds.roundMissedCount, noun: ("Aufgabe", "Aufgaben"),
                                  proceed: lesson.startNextRound, quit: { dismiss() })
            case .summary:
                SummaryView(
                    title: "Lektion fertig!",
                    lede: lesson.rounds.missedForms.isEmpty
                        ? "Alles auf Anhieb richtig. Ottimo lavoro!"
                        : "Ein paar Formen brauchten mehr als einen Versuch — die stehen unten noch mal.",
                    totalLabel: "Aufgaben", total: lesson.rounds.totalPlanned,
                    firstTry: lesson.rounds.firstTryCorrect, accuracy: lesson.rounds.accuracy,
                    missedTitle: "Diese Formen waren kniffelig", missed: lesson.rounds.missedForms,
                    back: { dismiss() },
                    repeatTitle: lesson.isPathLesson ? "Nächste Lektion" : "Lektion wiederholen",
                    repeatAction: lesson.start,
                    sections: summarySections)
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
                LessonTopBar(answered: lesson.rounds.roundAnswered, total: lesson.rounds.roundTotal) { dismiss() }

                VStack(spacing: 0) {
                    let isNew = lesson.newCells.contains(item.cell)
                    if lesson.rounds.round > 1 || isNew {
                        CardMeta(tag: isNew ? "Neu" : nil, round: lesson.rounds.round)
                            .padding(.bottom, 10)
                    }

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

    /// The German form, with the Italian infinitive and the tense underneath. The infinitive also
    /// tells apart verbs that share a German prompt (rimanere/restare = bleiben).
    private func prompt(item: ConjugationItem, verb: Verb) -> some View {
        VStack(spacing: 6) {
            let pronoun = Text(Pronoun.german(item.person, gender: item.gender) + "  ")
                .fontWeight(.regular)
                .foregroundStyle(Theme.inkSoft)
            Text("\(pronoun)\(verb.german(item.tense, item.person))")
                .font(Theme.display(30, weight: .semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Button { sheet = .verb(verb.infinitive) } label: {
                    Text(verb.infinitive).underline(color: Theme.goldSoft)
                }
                Text("·")
                Button { sheet = .tense(item.tense) } label: {
                    Text(item.tense.label).underline(color: Theme.goldSoft)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.bottom, 16)
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

    private var summarySections: [SummarySection] {
        guard let outcome = lesson.outcome else { return [] }
        var sections: [SummarySection] = []
        if let unlock = outcome.unlock {
            let cell = unlock.cell
            let row: SummarySection.Row = switch unlock.kind {
            case .verb: .init(label: "Neues Verb", value: "\(cell.verb) · \(cell.tense.label)")
            case .tense: .init(label: "Neue Zeit", value: "\(cell.verb) · \(cell.tense.label)")
            }
            sections.append(SummarySection(title: "Neu freigeschaltet", rows: [row], highlighted: true))
        }
        if !outcome.levelChanges.isEmpty {
            sections.append(SummarySection(title: "Stufen", rows: outcome.levelChanges.map {
                .init(label: "\($0.cell.verb) · \($0.cell.tense.label)", value: "\($0.from) → \($0.to)")
            }))
        }
        return sections
    }

    private func submit() {
        lesson.submit(answer)
    }
}
