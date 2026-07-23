import XCTest
@testable import Prvital

final class JournalDayHeadlineTests: XCTestCase {

    private func stats(
        readingCount: Int = 12,
        timeInRange: Double = 0,
        lowest: Double = 100,
        highest: Double = 140,
        entryCount extra: Int = 0
    ) -> JournalDayStats {
        var s = JournalDayStats()
        s.readingCount = readingCount
        s.timeInRange = timeInRange
        s.lowestMgdL = lowest
        s.highestMgdL = highest
        s.noteCount = extra // bumps entryCount without adding glucose
        return s
    }

    func testEmptyDayHasNoHeadline() {
        XCTAssertNil(JournalDayHeadline.make(stats: JournalDayStats(), targetLow: 70, targetHigh: 180))
    }

    func testNoGlucoseButLoggedEntries() {
        let s = stats(readingCount: 0, entryCount: 2)
        let h = JournalDayHeadline.make(stats: s, targetLow: 70, targetHigh: 180)
        XCTAssertEqual(h?.kind, .loggedOnly)
        XCTAssertEqual(h?.tone, .neutral)
    }

    func testStrongDayInRange() {
        let h = JournalDayHeadline.make(stats: stats(timeInRange: 0.82, lowest: 80, highest: 160),
                                        targetLow: 70, targetHigh: 180)
        XCTAssertEqual(h?.kind, .excellentRange)
        XCTAssertEqual(h?.tone, .positive)
    }

    func testFairlySteadyWhenMidRangeAndNoExtremes() {
        let h = JournalDayHeadline.make(stats: stats(timeInRange: 0.60, lowest: 80, highest: 175),
                                        targetLow: 70, targetHigh: 180)
        XCTAssertEqual(h?.kind, .goodRange)
        XCTAssertEqual(h?.tone, .neutral)
    }

    func testLowsCalledOutBeforeHighs() {
        // Mid-range TIR but both a low and a high — the low wins.
        let h = JournalDayHeadline.make(stats: stats(timeInRange: 0.55, lowest: 55, highest: 240),
                                        targetLow: 70, targetHigh: 180)
        XCTAssertEqual(h?.kind, .someLows)
        XCTAssertEqual(h?.tone, .caution)
    }

    func testHighsWhenNoLow() {
        let h = JournalDayHeadline.make(stats: stats(timeInRange: 0.55, lowest: 90, highest: 240),
                                        targetLow: 70, targetHigh: 180)
        XCTAssertEqual(h?.kind, .someHighs)
    }

    func testToughDayLeadsWithTheStandoutExtreme() {
        // Very low TIR with a low present → still surfaces the low.
        let h = JournalDayHeadline.make(stats: stats(timeInRange: 0.30, lowest: 50, highest: 260),
                                        targetLow: 70, targetHigh: 180)
        XCTAssertEqual(h?.kind, .someLows)
    }
}
