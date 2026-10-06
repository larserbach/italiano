import SwiftUI

enum InfoSheet: Identifiable {
    case tense(Tense)
    case verb(String)
    /// The verb sheet with the essere/avere level instead of the per-tense levels, for the Aux screens.
    case auxVerb(String)

    var id: String {
        switch self {
        case .tense(let tense): "tense-\(tense.rawValue)"
        case .verb(let verb): "verb-\(verb)"
        case .auxVerb(let verb): "aux-verb-\(verb)"
        }
    }
}

extension View {
    func infoSheet(_ sheet: Binding<InfoSheet?>, onDismiss: (() -> Void)? = nil) -> some View {
        self.sheet(item: sheet, onDismiss: onDismiss) { item in
            switch item {
            case .tense(let tense): TenseInfoView(tense: tense)
            case .verb(let verb): VerbInfoView(verb: VerbLibrary.verb(verb))
            case .auxVerb(let verb): VerbInfoView(verb: VerbLibrary.verb(verb), showsTenseLevels: false)
            }
        }
    }
}

struct VerbInfoView: View {
    let verb: Verb
    var showsTenseLevels = true
    @Environment(ProgressStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                SheetTitle(title: verb.infinitive) { dismiss() }
                Text("bedeutet auf Deutsch: „\(verb.meaning)“")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                Text("\(verb.groupLabel) · Passato prossimo mit \(verb.auxiliary.rawValue): \(verb.italian(.passatoprossimo, 0))")
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
                ControlLabel("Konjugation")
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                ConjugationTable(verb: verb)
                if showsTenseLevels {
                    ControlLabel("Fortschritt je Zeit")
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                    TenseBreakdown(levels: store.levels(of: verb.infinitive))
                } else {
                    ControlLabel("Level")
                        .padding(.top, 18)
                        .padding(.bottom, 4)
                    HStack(spacing: 10) {
                        VerbRing(level: store.auxLevel(of: verb.infinitive))
                        Text("Essere o avere?").font(.system(size: 14))
                    }
                }
            }
            .padding(24)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// All six forms of one tense, Italian next to German. Tense chips switch between tenses.
struct ConjugationTable: View {
    let verb: Verb
    @State private var tense: Tense = .presente

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Tense.allCases.filter(verb.hasTense)) { option in
                        Button(option.label) { tense = option }
                            .buttonStyle(ChipStyle(active: option == tense))
                    }
                }
                .padding(.vertical, 1)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                ForEach(Array(tense.persons), id: \.self) { person in
                    if let form = verb.tableForm(tense, person) {
                        GridRow {
                            Text(Pronoun.italian[person])
                                .foregroundStyle(Theme.inkSoft)
                            Text(form)
                                .fontWeight(.semibold)
                            Text(verb.german(tense, person))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .font(.system(size: 15))
                    }
                }
            }
            if verb.isGendered(tense) {
                Text("Mit essere passt sich das Partizip an: -o/-a im Singular, -i/-e im Plural.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .onAppear { if !verb.hasTense(tense) { tense = .presente } }
    }
}

/// One mastery ring per tense; tenses at level 0 are dimmed.
struct TenseBreakdown: View {
    let levels: [Tense: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Tense.allCases.filter { levels[$0] != nil }) { tense in
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
