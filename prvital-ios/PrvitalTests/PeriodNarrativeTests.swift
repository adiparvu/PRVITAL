import XCTest
@testable import Prvital

final class PeriodNarrativeTests: XCTestCase {

    private func stats(tir: Double, hypos: Int = 0, cv: Double = 0.30, count: Int = 500) -> PeriodStatistics {
        var s = PeriodStatistics()
        s.readingCount = count
        s.timeInRange = tir
        s.hypoEvents = hypos
        s.coefficientOfVariation = cv
        return s
    }

    func testRisingTIRLeadsTheStory() {
        let sentences = PeriodNarrative.sentences(
            current: stats(tir: 0.78), previous: stats(tir: 0.72), dailyDays: [])
        XCTAssertFalse(sentences.isEmpty)
        XCTAssertTrue(sentences[0].contains("78"))
    }

    func testSmallMoveReadsAsSteady() {
        let sentences = PeriodNarrative.sentences(
            current: stats(tir: 0.75), previous: stats(tir: 0.74), dailyDays: [])
        XCTAssertEqual(sentences.count, 1)
        XCTAssertTrue(sentences[0].contains("75"))
    }

    func testFewerLowsGetsASentence() {
        let sentences = PeriodNarrative.sentences(
            current: stats(tir: 0.75, hypos: 2), previous: stats(tir: 0.74, hypos: 6), dailyDays: [])
        XCTAssertTrue(sentences.contains { $0.contains("2") && $0.contains("6") })
    }

    func testNoPreviousPeriodSaysNothing() {
        let sentences = PeriodNarrative.sentences(
            current: stats(tir: 0.75), previous: nil, dailyDays: [])
        XCTAssertTrue(sentences.isEmpty)
    }

    func testToughestWeekdayNeedsRepetition() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        // Two full weeks where one weekday is clearly worse.
        var days: [DayTIR] = []
        for offset in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: start)!
            let weekday = calendar.component(.weekday, from: day)
            days.append(DayTIR(day: day, timeInRange: weekday == 3 ? 0.52 : 0.80, readingCount: 200))
        }
        let sentences = PeriodNarrative.sentences(
            current: stats(tir: 0.75), previous: stats(tir: 0.74), dailyDays: days)
        XCTAssertTrue(sentences.contains { $0.contains("52") })
    }

    func testCapsAtThreeSentences() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        var days: [DayTIR] = []
        for offset in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: start)!
            let weekday = calendar.component(.weekday, from: day)
            days.append(DayTIR(day: day, timeInRange: weekday == 3 ? 0.50 : 0.80, readingCount: 200))
        }
        let sentences = PeriodNarrative.sentences(
            current: stats(tir: 0.78, hypos: 2, cv: 0.28),
            previous: stats(tir: 0.70, hypos: 6, cv: 0.36),
            dailyDays: days)
        XCTAssertEqual(sentences.count, 3)
    }
}
