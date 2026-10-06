import Foundation
import Observation

/// One first-attempt answer with what it did to the form's memory.
struct AnswerLogEntry: Codable, Equatable, Identifiable {
    let date: Date
    let verb: String
    let tense: Tense
    let person: Int
    let gender: Gender?
    let rating: Rating
    /// The form's retrievability right before the answer, 0…1 (0 the first time).
    let retrievabilityBefore: Double
    /// The form's stability in days; nil before the very first answer.
    let stabilityBefore: Double?
    let stabilityAfter: Double

    var id: String { "\(date.timeIntervalSinceReferenceDate)|\(verb)|\(tense.rawValue)|\(person)" }
}

/// Every first answer, one JSON line each, so the verb detail screen can show what happened and
/// the data stays usable for fitting a scheduler later. Appends instead of rewriting the file.
@Observable
final class AnswerLog {
    static let maxEntries = 10_000

    private(set) var entries: [AnswerLogEntry]
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        let decoder = JSONDecoder()
        let lines = data.split(separator: UInt8(ascii: "\n"))
        entries = lines.compactMap { try? decoder.decode(AnswerLogEntry.self, from: Data($0)) }
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
            rewrite()
        }
    }

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("answer-log.jsonl")
    }

    func append(_ entry: AnswerLogEntry) {
        entries.append(entry)
        guard let fileURL, var line = try? JSONEncoder().encode(entry) else { return }
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: fileURL, options: .atomic)
        }
    }

    func entries(for verb: String) -> [AnswerLogEntry] { entries.filter { $0.verb == verb } }

    func reset() {
        entries = []
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func rewrite() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        var data = Data()
        for entry in entries {
            guard let line = try? encoder.encode(entry) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
