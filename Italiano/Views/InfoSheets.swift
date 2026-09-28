import SwiftUI

enum InfoSheet: Identifiable {
    case tense(Tense)
    case verb(String)

    var id: String {
        switch self {
        case .tense(let tense): "tense-\(tense.rawValue)"
        case .verb(let verb): "verb-\(verb)"
        }
    }
}

extension View {
    func infoSheet(_ sheet: Binding<InfoSheet?>, onDismiss: (() -> Void)? = nil) -> some View {
        self.sheet(item: sheet, onDismiss: onDismiss) { item in
            switch item {
            case .tense(let tense): TenseInfoView(tense: tense)
            case .verb(let verb): VerbInfoView(verb: VerbLibrary.verb(verb))
            }
        }
    }
}

struct VerbInfoView: View {
    let verb: Verb
    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SheetTitle(title: verb.infinitive) { dismiss() }
                Text("bedeutet auf Deutsch: „\(verb.meaning)“")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                Text("\(verb.group.rawValue) · Passato prossimo mit \(verb.auxiliary.rawValue): \(verb.italian(.passatoprossimo, 0))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 8)
                if let note = verb.spellingNote {
                    ControlLabel("Schreibung beachten")
                        .padding(.top, 14)
                    Text(note)
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ControlLabel("Level je Zeit")
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                TenseBreakdown(levels: Dictionary(uniqueKeysWithValues: Tense.allCases.map {
                    ($0, store.level(of: verb.infinitive, tense: $0))
                }))
            }
            .padding(24)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One mastery ring per tense; tenses not practised yet are dimmed.
struct TenseBreakdown: View {
    let levels: [Tense: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Tense.allCases) { tense in
                let level = levels[tense] ?? 0
                HStack(spacing: 10) {
                    VerbRing(level: level)
                    Text(tense.label).font(.system(size: 14))
                }
                .opacity(level == 0 ? 0.5 : 1)
            }
        }
    }
}

struct TenseInfoView: View {
    let tense: Tense
    @Environment(\.dismiss) private var dismiss

    private var info: TenseInfo { .of(tense) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    SheetTitle(title: tense.label) { dismiss() }
                    Text(info.translation)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSoft)
                }
                ForEach(info.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                        content(section.content)
                    }
                }
            }
            .padding(24)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func content(_ content: TenseInfo.Content) -> some View {
        switch content {
        case .paragraph(let text):
            Text(text).font(.system(size: 15)).lineSpacing(3)
        case .list(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.inkSoft)
                        Text(listText(item))
                            .font(.system(size: 15))
                            .lineSpacing(2)
                    }
                }
            }
        case .table(let columns, let rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(columns, id: \.self) { Text($0) }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                            Text(cell).foregroundStyle(index == 0 ? Theme.inkSoft : Theme.ink)
                        }
                    }
                    .font(.system(size: 14))
                    Divider().gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }
}

private func listText(_ item: TenseInfo.ListItem) -> AttributedString {
    var label = AttributedString(item.label + " ")
    label.font = .system(size: 15, weight: .semibold)
    return label + AttributedString(item.text)
}

private struct SheetTitle: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.display(24))
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
            }
            .accessibilityLabel("Schließen")
        }
    }
}
