import XCTest
@testable import Italiano

final class LessonRoundsTests: XCTestCase {
    func testAMissedItemComesBackInTheNextRoundAsARepeat() {
        var rounds = LessonRounds(["a", "b", "c"])
        XCTAssertTrue(rounds.isFirstAttempt)
        let missed = rounds.current
        rounds.recordMiss(key: "a", label: "A", answer: "a")
        rounds.advance()
        rounds.recordCorrect()
        rounds.advance()
        rounds.recordCorrect()
        rounds.advance()
        XCTAssertEqual(rounds.phase, .roundComplete)
        XCTAssertEqual(rounds.roundMissedCount, 1)

        rounds.startNextRound()
        XCTAssertEqual(rounds.current, missed)
        XCTAssertFalse(rounds.isFirstAttempt)
        XCTAssertEqual(rounds.roundTotal, 1)
        rounds.recordCorrect()
        rounds.advance()
        XCTAssertEqual(rounds.phase, .summary)
        XCTAssertEqual(rounds.firstTryCorrect, 2)
        XCTAssertEqual(rounds.missedForms.map(\.id), ["a"])
    }
}
