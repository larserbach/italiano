import Foundation

/// Retrievability (Abruf) over time for each person of a unit, rebuilt from the answer log. It jumps at every
/// first answer and fades in between. Between two answers it fades with the stability the first one left
/// (a Correct answer changes nothing, so the curve runs on), ending at the retrievability the log recorded
/// right before the second; after the last answer it follows the current memory.
enum RetrievabilityHistory {
    struct Point: Equatable {
        let date: Date
        let value: Double
    }

    /// Fading stretches get this many steps; answers within a few minutes of each other just get a straight line.
    static let steps = 16

    /// The curve per person that has answers, in the unit's order of persons.
    static func curves(of unit: PoolUnit, log: [AnswerLogEntry], memory: (MemoryKey) -> MemoryState?,
                       until now: Date) -> [(person: Int, points: [Point])] {
        let byKey = Dictionary(grouping: log) { MemoryKey(verb: $0.verb, tense: $0.tense, person: $0.person) }
        return zip(unit.persons, unit.keys).compactMap { person, key in
            guard let entries = byKey[key] else { return nil }
            return (person, curve(entries, current: memory(key), until: now))
        }
    }

    /// The value at `date`, between the two points around it; nil outside the curve.
    static func value(at date: Date, in points: [Point]) -> Double? {
        guard let first = points.first, let last = points.last, date >= first.date, date <= last.date else { return nil }
        guard let after = points.firstIndex(where: { $0.date > date }) else { return last.value }
        let (a, b) = (points[after - 1], points[after])
        let share = date.timeIntervalSince(a.date) / b.date.timeIntervalSince(a.date)
        return a.value + (b.value - a.value) * share
    }

    private static func curve(_ entries: [AnswerLogEntry], current: MemoryState?, until now: Date) -> [Point] {
        var points: [Point] = []
        for (index, entry) in entries.enumerated() {
            // The very first answer has nothing to fade from.
            if entry.stabilityBefore != nil { points.append(Point(date: entry.date, value: entry.retrievabilityBefore)) }
            let end: Date
            let value: (Date) -> Double
            if index + 1 < entries.count {
                let next = entries[index + 1]
                end = next.date
                value = { min(1, next.retrievabilityBefore * pow(2, MemoryState.days(from: $0, to: next.date) / entry.stabilityAfter)) }
            } else if let current {
                end = max(entry.date, now)
                value = current.retrievability(at:)
            } else {
                break
            }
            let span = end.timeIntervalSince(entry.date)
            let count = MemoryState.days(from: entry.date, to: end) < 0.01 ? 1 : steps
            for step in 0...count {
                let date = entry.date + span * Double(step) / Double(count)
                points.append(Point(date: date, value: value(date)))
            }
        }
        return points
    }
}
