import XCTest
@testable import Italiano

final class AnswerHistoryTests: XCTestCase {
    private var url: URL!
    private var calendar: Calendar!
    /// Wednesday, 24 September 2026, noon in Berlin.
    private let now = ISO8601DateFormatter().date(from: "2026-09-24T10:00:00Z")!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }

    func testRecordAggregatesAndPersists() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        history.record(verb: "parlare", tense: .presente, correct: true, on: now)
        history.record(verb: "parlare", tense: .presente, correct: false, on: now)
        history.record(verb: "parlare", tense: .futuro, correct: true, on: now)
        history.record(verb: "capire", tense: .presente, correct: false, on: daysAgo(1))

        let reloaded = AnswerHistory(fileURL: url, calendar: calendar)
        let window = reloaded.window(for: .days14, now: now)
        XCTAssertEqual(reloaded.totals(in: window, tense: .presente), AnswerCounts(correct: 1, mistakes: 2))
        XCTAssertEqual(reloaded.totals(in: window, tense: nil), AnswerCounts(correct: 2, mistakes: 2))
        XCTAssertEqual(reloaded.days.count, 2)
    }

    func testDayBucketsIncludeEmptyDaysAndEndToday() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        history.record(verb: "parlare", tense: .presente, correct: true, on: daysAgo(3))
        history.record(verb: "parlare", tense: .presente, correct: false, on: daysAgo(20)) // outside 14 days

        let window = history.window(for: .days14, now: now)
        XCTAssertEqual(window.unit, .day)
        let buckets = history.buckets(in: window, tense: .presente)
        XCTAssertEqual(buckets.count, 14)
        XCTAssertEqual(buckets.last?.start, calendar.startOfDay(for: now))
        XCTAssertEqual(buckets.map(\.counts.total).reduce(0, +), 1)
        XCTAssertEqual(buckets[10].counts.correct, 1)
        XCTAssertEqual(history.window(for: .days3, now: now).bucketStarts.count, 3)
    }

    func testOverviewBucketsSumAllTenses() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        history.record(verb: "parlare", tense: .presente, correct: true, on: now)
        history.record(verb: "parlare", tense: .futuro, correct: false, on: now)
        history.record(verb: "capire", tense: .imperfetto, correct: true, on: daysAgo(1))

        let buckets = history.buckets(in: history.window(for: .days3, now: now), tense: nil)
        XCTAssertEqual(buckets.map(\.counts), [AnswerCounts(),
                                               AnswerCounts(correct: 1, mistakes: 0),
                                               AnswerCounts(correct: 1, mistakes: 1)])
    }

    func testLongerRangesUseWeeksAndMonths() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        let sixMonths = history.window(for: .months6, now: now)
        XCTAssertEqual(sixMonths.unit, .weekOfYear)
        XCTAssertTrue((26...28).contains(sixMonths.bucketStarts.count))
        let year = history.window(for: .months12, now: now)
        XCTAssertEqual(year.unit, .month)
        XCTAssertEqual(year.bucketStarts.count, 12)
    }

    func testAllRangeKeepsBucketCountSmall() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        history.record(verb: "parlare", tense: .presente, correct: true, on: daysAgo(10))
        XCTAssertEqual(history.window(for: .all, now: now).unit, .day)
        history.record(verb: "parlare", tense: .presente, correct: true, on: daysAgo(100))
        let window = history.window(for: .all, now: now)
        XCTAssertEqual(window.unit, .weekOfYear)
        XCTAssertLessThanOrEqual(window.bucketStarts.count, AnswerHistory.maxBuckets)
        XCTAssertEqual(history.totals(in: window, tense: nil).total, 2)
    }

    func testGroupsSplitAuxiliaryOnlyInPassatoProssimo() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        for tense in [Tense.passatoprossimo, .presente] {
            history.record(verb: "parlare", tense: tense, correct: true, on: now)
            history.record(verb: "tornare", tense: tense, correct: false, on: now)
            history.record(verb: "capire", tense: tense, correct: true, on: now)
        }
        let window = history.window(for: .days14, now: now)
        XCTAssertEqual(history.byGroup(in: window, tense: .passatoprossimo).map(\.label),
                       ["-are mit avere", "-are mit essere", "-ire (isc)"])
        let presente = history.byGroup(in: window, tense: .presente)
        XCTAssertEqual(presente.map(\.label), ["-are", "-ire (isc)"])
        XCTAssertEqual(presente.first?.counts, AnswerCounts(correct: 1, mistakes: 1))
    }

    func testTopMistakesSortedByMistakes() {
        let history = AnswerHistory(fileURL: url, calendar: calendar)
        for _ in 0..<3 { history.record(verb: "viaggiare", tense: .futuro, correct: false, on: now) }
        history.record(verb: "viaggiare", tense: .futuro, correct: true, on: now)
        history.record(verb: "sciare", tense: .futuro, correct: false, on: now)
        history.record(verb: "parlare", tense: .futuro, correct: true, on: now)
        let top = history.topMistakes(in: history.window(for: .days3, now: now), tense: .futuro)
        XCTAssertEqual(top.map(\.verb), ["viaggiare", "sciare"])
        XCTAssertEqual(top.first?.counts, AnswerCounts(correct: 1, mistakes: 3))
    }

    func testLessonCountsFirstAttemptsOnly() {
        let defaults = UserDefaults(suiteName: "AnswerHistoryTests")!
        defaults.removePersistentDomain(forName: "AnswerHistoryTests")
        // The statistics window is relative to the real date.
        let store = makeStore(defaults, clock: TestClock(now: .now), historyURL: url)
        store.conjugation.verbs = ["parlare"]
        store.conjugation.tenses = [.presente]
        store.conjugation.length = .count(1)
        let lesson = ConjugationLesson(store: store)
        lesson.submit("sbagliato")
        lesson.submit("") // Verstanden
        XCTAssertEqual(lesson.phase, .roundComplete)
        lesson.startNextRound()
        lesson.submit(lesson.current!.answer) // correct in the repeat round

        let window = store.history.window(for: .days3)
        XCTAssertEqual(store.history.totals(in: window, tense: .presente), AnswerCounts(correct: 0, mistakes: 1))
    }
}
