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
            VStack(spacing: 0) {
                LessonTopBar(answered: lesson.rounds.roundAnswered, total: lesson.rounds.roundTotal) { dismiss() }
                    .padding(.bottom, 22)

                let isNew = lesson.newUnits.contains(item.unit)
                if lesson.rounds.round > 1 || isNew {
                    CardMeta(tag: isNew ? "Neu" : nil, round: lesson.rounds.round)
                        .padding(.bottom, 10)
                }

                prompt(item: item, verb: verb)

                AnswerField(text: $answer, isEditable: !lesson.isReviewing,
                            focusToken: focusToken, onSubmit: submit)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(fieldBackground, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(fieldBorder, lineWidth: 1.5))

                feedbackText
                    .font(.system(size: 14))
                    .frame(minHeight: 20)
                    .padding(.top, 10)

                Spacer(minLength: 16)

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
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    /// The German form, with the Italian infinitive and the tense underneath. The infinitive also
    /// tells apart verbs that share a German prompt (rimanere/restare = bleiben).
    private func prompt(item: ConjugationItem, verb: Verb) -> some View {
        VStack(spacing: 6) {
            let pronoun = Text(Pronoun.german(item.person, gender: item.gender))
                .fontWeight(.regular)
                .foregroundStyle(Theme.inkSoft)
            // In the passato prossimo an italic m or f always follows the pronoun.
            let marker = Text(item.marker.map { " \($0)" } ?? "")
                .font(Theme.display(22, weight: .medium).italic())
                .foregroundStyle(Theme.gold)
            Text("\(pronoun)\(marker)  \(verb.german(item.tense, item.person))")
                .font(Theme.display(30, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityLabel(spokenPrompt(item: item, verb: verb))
            HStack(spacing: 6) {
                Button {
                    lesson.noteLookup()
                    sheet = .verb(verb.infinitive)
                } label: {
                    Text(verb.infinitive).underline(color: Theme.goldSoft)
                }
                Text("·")
                Button {
                    lesson.noteLookup()
                    sheet = .tense(item.tense)
                } label: {
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

    private func spokenPrompt(item: ConjugationItem, verb: Verb) -> String {
        var pronoun = Pronoun.german(item.person, gender: item.gender)
        if let gender = item.gender { pronoun += ", \(gender.spokenName)," }
        return "\(pronoun) \(verb.german(item.tense, item.person))"
    }

    @ViewBuilder
    private var feedbackText: some View {
        switch lesson.feedback {
        case .none: Text(" ")
        case .correct(let answer):
            Text(lesson.lookedUp ? "Giusto! \(answer) · nachgeschaut, zählt halb" : "Giusto! \(answer)")
                .foregroundStyle(Theme.olive)
        case .almost(let answer):
            Text("Fast richtig! Geschrieben wird: \(answer) · zählt halb").foregroundStyle(Theme.gold)
        case .wrong(let answer): Text("Nicht ganz — richtig wäre: \(answer)").foregroundStyle(Theme.brick)
        case .wrongGender(let answer):
            Text("Fast — das Partizip passt sich an (\(genderHint)): \(answer)").foregroundStyle(Theme.brick)
        case .revealed(let answer): Text(answer)
        }
    }

    private var fieldBackground: Color {
        switch lesson.feedback {
        case .correct: Theme.oliveBackground
        case .almost: Theme.goldSoft.opacity(0.5)
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
        lesson.current?.gender?.spokenName ?? ""
    }

    private var summarySections: [SummarySection] {
        guard let outcome = lesson.outcome else { return [] }
        var sections: [SummarySection] = []
        if !outcome.additions.isEmpty {
            sections.append(SummarySection(title: "Neu im Pool", rows: outcome.additions.map {
                .init(label: "dank \($0.cause.label)", value: $0.unit.label)
            }, highlighted: true))
        }
        if !outcome.changes.isEmpty {
            sections.append(SummarySection(title: "Gut in den letzten \(Curriculum.windowSize) Antworten", rows: outcome.changes.map {
                .init(label: $0.unit.label, value: "\($0.from.map(DaysText.percent) ?? "neu") → \($0.to.map(DaysText.percent) ?? "–")")
            }))
        }
        return sections
    }

    private func submit() {
        lesson.submit(answer)
    }
}
