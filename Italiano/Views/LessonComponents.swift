import SwiftUI

/// Close, mute, and how far the learner is through the current round.
struct LessonTopBar: View {
    let answered: Int
    let total: Int
    let quit: () -> Void
    @Environment(ProgressStore.self) private var store
    @Environment(\.speech) private var speech

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton("xmark", label: "Abbrechen", action: quit)
                // The same switch as in the settings, so muting here mutes every exercise.
                IconButton(store.readAloud ? "speaker.wave.2" : "speaker.slash", label: "Vorlesen") {
                    store.readAloud.toggle()
                    if !store.readAloud { speech.stop() }
                }
                .accessibilityValue(store.readAloud ? "An" : "Aus")
            }
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
                // Room for "20/20", so the bar keeps its length as the count grows.
                .frame(minWidth: 46, alignment: .trailing)
        }
    }
}

/// The line above a card's prompt: a tag ("Neu", the tense) and the repeat round.
struct CardMeta: View {
    let tag: String?
    let round: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let tag {
                Text(tag)
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

/// Whether a share went up or down, as the summary shows it: by the rounded percentages, so 45 % → 45 % is no change.
enum Trend {
    case up, down, same

    /// Nil when there is no value before, for something new.
    init?(from: Double?, to: Double?) {
        guard let from, let to else { return nil }
        let (a, b) = (Int((from * 100).rounded()), Int((to * 100).rounded()))
        self = b > a ? .up : b < a ? .down : .same
    }
}

/// An extra list in the lesson summary, such as what the lesson unlocked.
struct SummarySection: Identifiable {
    struct Row: Identifiable {
        let label: String
        let value: String
        /// Shown after the value as an arrow.
        var trend: Trend? = nil
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
    /// The forms that needed more than one try, with the right answer; left out where the sections say more.
    var missedTitle = ""
    var missed: [MissedForm] = []
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
        // Where some rows have an arrow, the others keep its space, so the values line up.
        let trends = rows.contains { $0.trend != nil }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text(row.value).fontWeight(.semibold).monospacedDigit()
                    if let trend = row.trend {
                        TrendArrow(trend: trend)
                    } else if trends {
                        Color.clear.frame(width: 14, height: 1)
                    }
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

/// Green up, red down, a grey dash for no change.
private struct TrendArrow: View {
    let trend: Trend

    var body: some View {
        let (symbol, color, label) = switch trend {
        case .up: ("arrow.up", Theme.olive, "gestiegen")
        case .down: ("arrow.down", Theme.brick, "gesunken")
        case .same: ("minus", Theme.inkSoft, "unverändert")
        }
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 14)
            .accessibilityLabel(label)
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
