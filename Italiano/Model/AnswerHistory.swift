import Foundation
import Observation

/// Correct answers and mistakes, counting first attempts only.
struct AnswerCounts: Codable, Equatable {
    var correct = 0
    var mistakes = 0

    var total: Int { correct + mistakes }
    /// Share of correct answers in percent, or nil without answers.
    var accuracy: Int? { total == 0 ? nil : Int((Double(correct) / Double(total) * 100).rounded()) }

    static func + (lhs: AnswerCounts, rhs: AnswerCounts) -> AnswerCounts {
        AnswerCounts(correct: lhs.correct + rhs.correct, mistakes: lhs.mistakes + rhs.mistakes)
    }

    static func += (lhs: inout AnswerCounts, rhs: AnswerCounts) { lhs = lhs + rhs }
}

enum StatsRange: String, CaseIterable, Identifiable {
    case days3, days14, months3, months6, months12, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .days3: "3 T"
        case .days14: "14 T"
        case .months3: "3 M"
        case .months6: "6 M"
        case .months12: "12 M"
        case .all: "Alle"
        }
    }
}

/// The time axis of a chart: where it starts and how wide one bar is.
struct StatsWindow {
    let unit: Calendar.Component
    let bucketStarts: [Date]
    var start: Date { bucketStarts.first! }
}

struct StatsBucket: Identifiable {
    let start: Date
    let counts: AnswerCounts
    var id: Date { start }
}

struct GroupStats: Identifiable {
    let label: String
    let counts: AnswerCounts
    var id: String { label }
}

struct VerbMistakes: Identifiable {
    let verb: String
    let counts: AnswerCounts
    var id: String { verb }
}

/// Answer log for the statistics, aggregated per day and verb×tense. A day is the finest
/// resolution any chart needs, so this stays small even after years of practice.
@Observable
final class AnswerHistory {
    static let maxBuckets = 31

    /// "yyyy-MM-dd" → "verb|tense" → counts
    private(set) var days: [String: [String: AnswerCounts]]
    let calendar: Calendar
    private let fileURL: URL?
    /// "yyyy-MM-dd" in the calendar's time zone. Built once: queries parse every stored day.
    private let formatter: DateFormatter

    init(fileURL: URL?, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.formatter = formatter
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: [String: AnswerCounts]].self, from: data) {
            days = stored
        } else {
            days = [:]
        }
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("answer-history.json")
    }

    // MARK: Recording

    func record(verb: String, tense: Tense, correct: Bool, on date: Date = .now) {
        let cell = "\(verb)|\(tense.rawValue)"
        var counts = days[dayKey(date), default: [:]][cell, default: AnswerCounts()]
        if correct { counts.correct += 1 } else { counts.mistakes += 1 }
        days[dayKey(date), default: [:]][cell] = counts
        save()
    }

    func reset() {
        days = [:]
        save()
    }

    var firstDay: Date? { days.keys.min().flatMap { date(fromKey: $0) } }
    var isEmpty: Bool { days.isEmpty }

    // MARK: Queries

    func window(for range: StatsRange, now: Date = .now) -> StatsWindow {
        let today = calendar.startOfDay(for: now)
        func back(_ component: Calendar.Component, _ value: Int) -> Date {
            calendar.date(byAdding: component, value: -value, to: today)!
        }
        let unit: Calendar.Component
        let from: Date
        switch range {
        case .days3: unit = .day; from = back(.day, 2)
        case .days14: unit = .day; from = back(.day, 13)
        case .months3: unit = .weekOfYear; from = back(.month, 3)
        case .months6: unit = .weekOfYear; from = back(.month, 6)
        case .months12: unit = .month; from = back(.month, 11)
        case .all:
            let first = min(firstDay ?? today, today)
            unit = [Calendar.Component.day, .weekOfYear, .month]
                .first { bucketStarts(from: first, to: now, unit: $0).count <= Self.maxBuckets } ?? .month
            from = first
        }
        return StatsWindow(unit: unit, bucketStarts: bucketStarts(from: from, to: now, unit: unit))
    }

    /// One bucket per bar, including empty ones so gaps stay visible.
    func buckets(in window: StatsWindow, tense: Tense?) -> [StatsBucket] {
        var sums = Dictionary(uniqueKeysWithValues: window.bucketStarts.map { ($0, AnswerCounts()) })
        for entry in entries(in: window) where tense == nil || entry.tense == tense {
            guard let start = calendar.dateInterval(of: window.unit, for: entry.day)?.start,
                  let sum = sums[start] else { continue }
            sums[start] = sum + entry.counts
        }
        return window.bucketStarts.map { StatsBucket(start: $0, counts: sums[$0]!) }
    }

    func totals(in window: StatsWindow, tense: Tense?) -> AnswerCounts {
        entries(in: window)
            .filter { tense == nil || $0.tense == tense }
            .reduce(AnswerCounts()) { $0 + $1.counts }
    }

    /// In the Passato prossimo the auxiliary matters, so -are verbs are split into avere and essere.
    /// In all other tenses only the ending group does.
    func byGroup(in window: StatsWindow, tense: Tense) -> [GroupStats] {
        var sums: [String: (rank: Int, counts: AnswerCounts)] = [:]
        for (key, counts) in countsPerVerb(in: window, tense: tense) {
            let (rank, label) = Self.statsGroup(VerbLibrary.verb(key), tense: tense)
            sums[label, default: (rank, AnswerCounts())].counts += counts
        }
        return sums.sorted { $0.value.rank < $1.value.rank }
            .map { GroupStats(label: $0.key, counts: $0.value.counts) }
    }

    /// A verb's row in `byGroup`, with a rank that orders rows like the verb picker.
    private static func statsGroup(_ verb: Verb, tense: Tense) -> (rank: Int, label: String) {
        if verb.isIrregular { return (Int.max, "Unregelmäßig") }
        let rank = 2 * VerbGroup.allCases.firstIndex(of: verb.group)!
        if tense == .passatoprossimo, verb.group == .are {
            return (verb.auxiliary == .avere ? rank : rank + 1, "-are mit \(verb.auxiliary.rawValue)")
        }
        return (rank, verb.group.rawValue)
    }

    func topMistakes(in window: StatsWindow, tense: Tense, limit: Int = 3) -> [VerbMistakes] {
        countsPerVerb(in: window, tense: tense)
            .filter { $0.value.mistakes > 0 }
            .map { VerbMistakes(verb: $0.key, counts: $0.value) }
            .sorted { ($0.counts.mistakes, $1.verb) > ($1.counts.mistakes, $0.verb) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Private

    private func countsPerVerb(in window: StatsWindow, tense: Tense) -> [String: AnswerCounts] {
        var result: [String: AnswerCounts] = [:]
        for entry in entries(in: window) where entry.tense == tense {
            result[entry.verb, default: AnswerCounts()] += entry.counts
        }
        return result
    }

    private typealias Entry = (day: Date, verb: String, tense: Tense, counts: AnswerCounts)

    private func entries(in window: StatsWindow) -> [Entry] {
        var result: [Entry] = []
        for (key, cells) in days {
            guard let day = date(fromKey: key), day >= window.start else { continue }
            for (cell, counts) in cells {
                let parts = cell.split(separator: "|").map(String.init)
                guard parts.count == 2, let tense = Tense(rawValue: parts[1]) else { continue }
                result.append((day: day, verb: parts[0], tense: tense, counts: counts))
            }
        }
        return result
    }

    private func bucketStarts(from: Date, to now: Date, unit: Calendar.Component) -> [Date] {
        guard var current = calendar.dateInterval(of: unit, for: from)?.start else { return [calendar.startOfDay(for: now)] }
        var starts: [Date] = []
        while current <= now {
            starts.append(current)
            current = calendar.date(byAdding: unit, value: 1, to: current)!
        }
        return starts
    }

    private func dayKey(_ date: Date) -> String { formatter.string(from: date) }
    private func date(fromKey key: String) -> Date? { formatter.date(from: key) }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(days) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
