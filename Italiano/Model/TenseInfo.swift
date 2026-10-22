/// The explanation sheet for one tense. The texts are in TenseInfo+Content.swift.
struct TenseInfo {
    struct Section: Identifiable {
        let heading: String
        let content: Content
        var id: String { heading }
    }

    struct ListItem: Identifiable {
        let label: String
        let text: String
        var id: String { label + text }
    }

    enum Content {
        case paragraph(String)
        case list([ListItem])
        /// `rows` start with the pronoun, followed by one cell per column.
        case table(columns: [String], rows: [[String]])
    }

    /// The German counterpart, shown under the title.
    let translation: String
    let sections: [Section]

    static func of(_ tense: Tense) -> TenseInfo { all[tense]! }
}
