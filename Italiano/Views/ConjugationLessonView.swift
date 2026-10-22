import SwiftUI

struct ConjugationLessonView: View {
    /// Created by the caller, once per lesson. Building it here would start a new lesson on every redraw
    /// of the screen behind, and each new lesson stops whatever is being read aloud.
    private let lesson: ConjugationLesson
    @State private var answer = ""
    /// Bumped to focus the answer field again: on every new card and after a sheet closes.
    @State private var focusToken = 0
    @State private var sheet: InfoSheet?
    @Environment(\.dismiss) private var dismiss

    init(lesson: ConjugationLesson) {
        self.lesson = lesson
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

                Spacer(minLength: 22)

                VStack(spacing: 0) {
                    let isNew = lesson.newUnits.contains(item.unit)
                    if lesson.rounds.round > 1 || isNew {
                        CardMeta(tag: isNew ? "Neu" : nil, round: lesson.rounds.round)
                            .padding(.bottom, 10)
                    }

                    prompt(item: item, verb: verb)
                }
                // The feedback hangs below the prompt, so the card stays centred when it appears.
                .overlay(alignment: .bottom) {
                    feedbackText
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .alignmentGuide(.bottom) { $0[.top] }
                }

                // Leaves room for two lines of feedback.
                Spacer(minLength: 60)

                answerBox
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    /// The answer area: a text box in iOS glass, with the hint and submit buttons tucked into its corner.
    private var answerBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            AnswerField(text: $answer, isEditable: !lesson.isReviewing,
                        focusToken: focusToken, onSubmit: submit)
                .frame(height: 30)

            HStack(spacing: 8) {
                Spacer()
                if !lesson.isReviewing {
                    Button(action: lesson.reveal) {
                        Image(systemName: "questionmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(Theme.ink)
                    .accessibilityLabel("Ich weiß es nicht")
                }
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.gold)
                .accessibilityLabel(lesson.isReviewing ? "Verstanden" : "Prüfen")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 96)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { focusToken += 1 }
        .glassEffect(.regular.tint(fieldTint), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            if let fieldBorder {
                RoundedRectangle(cornerRadius: 24).strokeBorder(fieldBorder, lineWidth: 1.5)
            }
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
        .padding(.bottom, 40)
    }

    /// For VoiceOver, with the m/f marker spelled out (männlich, weiblich).
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

    /// Colours the glass after an answer; nil keeps the plain glass while typing.
    private var fieldTint: Color? {
        switch lesson.feedback {
        case .correct: Theme.olive.opacity(0.25)
        case .almost: Theme.gold.opacity(0.25)
        case .wrong, .wrongGender: Theme.brick.opacity(0.25)
        default: nil
        }
    }

    private var fieldBorder: Color? {
        switch lesson.feedback {
        case .correct: Theme.olive
        case .almost: Theme.gold
        case .wrong, .wrongGender: Theme.brick
        default: nil
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
