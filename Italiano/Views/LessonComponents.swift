import SwiftUI

struct LessonTopBar: View {
    let answered: Int
    let total: Int
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Abbrechen", action: quit)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
            GeometryReader { geo in
                Capsule().fill(Theme.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.gold)
                            .frame(width: total == 0 ? 0 : geo.size.width * min(1, CGFloat(answered) / CGFloat(total)))
                            .animation(.easeOut(duration: 0.25), value: answered)
                    }
            }
            .frame(height: 6)
            Text("\(answered)/\(total)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .monospacedDigit()
                .frame(minWidth: 46, alignment: .trailing)
        }
    }
}

struct CardMeta: View {
    let tag: String?
    let round: Int
    var onTagTap: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let tag {
                if let onTagTap {
                    Button(action: onTagTap) {
                        Text(tag).underline(color: Theme.goldSoft)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(tag)
                }
            }
            if round > 1 {
                Text("Wiederholungsrunde \(round)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(Theme.gold)
    }
}

struct RoundCompleteView: View {
    let round: Int
    let correct: Int
    let total: Int
    let missedCount: Int
    let noun: (singular: String, plural: String)
    let proceed: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ScreenHeader(title: "Runde \(round) geschafft!",
                         lede: "\(correct) von \(total) richtig. Jetzt wiederholen wir deine Fehler.")
                .padding(.bottom, 18)
            Button("Fehler wiederholen (\(missedCount) \(missedCount == 1 ? noun.singular : noun.plural))", action: proceed)
                .buttonStyle(PrimaryButtonStyle())
            Button("Abbrechen", action: quit)
                .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 32)
    }
}

/// An extra list in the lesson summary, such as what the lesson unlocked.
struct SummarySection: Identifiable {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let title: String
    let rows: [Row]
    var highlighted = false
    var id: String { title }
}

struct SummaryView: View {
    let title: String
    let lede: String
    let totalLabel: String
    let total: Int
    let firstTry: Int
    let accuracy: Int
    let missedTitle: String
    let missed: [MissedForm]
    let back: () -> Void
    let repeatTitle: String
    let repeatAction: () -> Void
    /// Shown between the stats and the missed forms.
    var sections: [SummarySection] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ScreenHeader(title: title, lede: lede)
                HStack(spacing: 10) {
                    StatTile(value: "\(total)", label: totalLabel)
                    StatTile(value: "\(firstTry)", label: "Auf Anhieb")
                    StatTile(value: "\(accuracy)%", label: "Trefferquote")
                }
                ForEach(sections) { section in
                    let list = rowList(section.rows)
                    if section.highlighted {
                        VStack(alignment: .leading, spacing: 4) {
                            ControlLabel(section.title)
                            list.padding(.horizontal, 10)
                                .background(Theme.goldSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.gold))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ControlLabel(section.title)
                            list
                        }
                    }
                }
                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ControlLabel(missedTitle)
                        rowList(missed.map { SummarySection.Row(label: $0.label, value: $0.answer) })
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(action: back) {
                    Image(systemName: "arrow.left").frame(width: 20)
                }
                .buttonStyle(GhostButtonStyle(fullWidth: false))
                .accessibilityLabel("Neue Einstellungen")
                Button(repeatTitle, action: repeatAction)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.paper.ignoresSafeArea(edges: .bottom))
        }
    }

    private func rowList(_ rows: [SummarySection.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text(row.value).fontWeight(.semibold)
                }
                .font(.system(size: 14.5))
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(26))
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

/// The pronoun in front of the answer field. When the answer depends on the subject's
/// gender, an italic m or f follows it (lui and lei show it through the pronoun itself).
struct PronounLabel: View {
    let pronoun: String
    let gender: Gender?
    let marker: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(pronoun)
                .font(Theme.display(17, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
            if let marker {
                Text(marker)
                    .font(Theme.display(14, weight: .medium).italic())
                    .foregroundStyle(Theme.gold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gender.map { "\(pronoun), \($0.spokenName)" } ?? pronoun)
    }
}
