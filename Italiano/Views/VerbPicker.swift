import SwiftUI

/// The verb chips of the Essere o avere? settings, in the sections of `VerbLibrary.groups`, each with its ring.
struct VerbPicker: View {
    @Binding var selection: Set<String>
    let level: (String) -> Int
    /// Adds "Verb-Details" to the long-press menu.
    var onDetails: ((String) -> Void)? = nil

    @AppStorage(Tutorial.verbRing.defaultsKey) private var coachSeen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !coachSeen {
                CoachMark(text: "Der Ring zeigt das Level des Verbs.",
                          dismiss: { withAnimation { coachSeen = true } })
                    .transition(.opacity)
            }
            ForEach(VerbLibrary.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    let allSelected = group.verbs.allSatisfy(selection.contains)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(group.label)
                            .font(Theme.display(13, weight: .regular))
                            .foregroundStyle(Theme.gold)
                        Spacer(minLength: 0)
                        Button(allSelected ? "Alle abwählen" : "Alle auswählen") {
                            if allSelected {
                                let rest = selection.subtracting(group.verbs)
                                // At least one verb always stays selected.
                                selection = rest.isEmpty ? Set(group.verbs.prefix(1)) : rest
                            } else {
                                selection.formUnion(group.verbs)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Theme.gold.opacity(0.6), lineWidth: 1))
                        .contentShape(Capsule())
                        .fixedSize()
                    }
                    FlowLayout {
                        ForEach(group.verbs, id: \.self) { verb in
                            Button {
                                selection.toggleKeepingOne(verb)
                            } label: {
                                HStack(spacing: 7) {
                                    VerbRing(level: level(verb))
                                    Text(verb)
                                }
                                // Pulls the ring into the chip's padding, so it is no taller than a plain chip.
                                .padding(.leading, -6)
                                .padding(.vertical, -2)
                            }
                            .buttonStyle(ChipStyle(active: selection.contains(verb)))
                            .modifier(VerbPreviewMenu(verb: verb,
                                                      level: level(verb),
                                                      onDetails: onDetails.map { onDetails in
                                { verb in
                                    // Whoever found the long-press doesn't need the hint any more.
                                    coachSeen = true
                                    onDetails(verb)
                                }
                            }))
                        }
                    }
                }
            }
        }
    }
}

private struct CoachMark: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Verstanden", action: dismiss)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.gold)
        }
        .padding(12)
        .background(Theme.goldSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.gold))
    }
}

/// Long-press on a verb chip: previews basic facts about the verb (meaning, group, Passato prossimo) and its
/// level, with a link to the verb sheet.
private struct VerbPreviewMenu: ViewModifier {
    let verb: String
    let level: Int
    let onDetails: ((String) -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let onDetails {
                Button("Verb-Details", systemImage: "info.circle") { onDetails(verb) }
            }
        } preview: {
            BasicVerbInfo(verb: VerbLibrary.verb(verb), level: level)
                .padding(18)
                .frame(width: 300, alignment: .leading)
                .background(Theme.paper)
                .foregroundStyle(Theme.ink)
        }
    }
}

private struct BasicVerbInfo: View {
    let verb: Verb
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verb.infinitive).font(Theme.display(20))
                Spacer()
                VerbRing(level: level)
            }
            Text("bedeutet auf Deutsch: „\(verb.meaning)“")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSoft)
            Text(verb.groupLabel)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
            Text("Passato prossimo: \(verb.italian(.passatoprossimo, 0))")
                .font(.system(size: 14))
                .padding(.top, 4)
        }
    }
}

extension Set {
    /// Toggles membership but never removes the last element.
    mutating func toggleKeepingOne(_ element: Element) {
        if contains(element) {
            if count > 1 { remove(element) }
        } else {
            insert(element)
        }
    }
}
