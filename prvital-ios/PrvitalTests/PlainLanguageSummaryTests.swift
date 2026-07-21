import XCTest
@testable import Prvital

final class PlainLanguageSummaryTests: XCTestCase {

    private func stats(
        count: Int = 200, avg: Double = 130, tir: Double = 0.75,
        below: Double = 0, above: Double = 0, veryLow: Double = 0, cv: Double = 0.30
    ) -> PeriodStatistics {
        var s = PeriodStatistics()
        s.readingCount = count
        s.average = avg
        s.timeInRange = tir
        s.timeBelowRange = below
        s.timeAboveRange = above
        s.timeVeryLow = veryLow
        s.coefficientOfVariation = cv
        s.glucoseManagementIndicator = 3.31 + 0.02392 * avg
        return s
    }

    func testEmptyStatsExplainsGap() {
        let summary = PlainLanguageSummarizer.summary(
            stats: PeriodStatistics(), period: .today, goalFraction: 0.70, unit: .mgdL)
        XCTAssertEqual(summary.sentences.count, 1)
        XCTAssertTrue(summary.sentences[0].lowercased().contains("enough"))
    }

    func testMeetingGoalIsCelebrated() {
        let summary = PlainLanguageSummarizer.summary(
            stats: stats(tir: 0.80), period: .today, goalFraction: 0.70, unit: .mgdL)
        XCTAssertTrue(summary.sentences[0].contains("80%"))
        // Always includes an average / A1c line.
        XCTAssertTrue(summary.sentences.contains { $0.contains("A1c") })
    }

    func testVeryLowIsSurfaced() {
        let summary = PlainLanguageSummarizer.summary(
            stats: stats(tir: 0.6, below: 0.08, veryLow: 0.02), period: .week, goalFraction: 0.70, unit: .mgdL)
        XCTAssertTrue(summary.sentences.contains { $0.lowercased().contains("very low") })
    }

    func testSteadyVsVariable() {
        let steady = PlainLanguageSummarizer.summary(
            stats: stats(cv: 0.30), period: .today, goalFraction: 0.70, unit: .mgdL)
        XCTAssertTrue(steady.sentences.contains { $0.lowercased().contains("steady") })

        let swingy = PlainLanguageSummarizer.summary(
            stats: stats(cv: 0.45), period: .today, goalFraction: 0.70, unit: .mgdL)
        XCTAssertTrue(swingy.sentences.contains { $0.lowercased().contains("swung") })
    }

    func testMmolDoesNotCrash() {
        let summary = PlainLanguageSummarizer.summary(
            stats: stats(), period: .today, goalFraction: 0.70, unit: .mmolL)
        XCTAssertFalse(summary.sentences.isEmpty)
    }
}
