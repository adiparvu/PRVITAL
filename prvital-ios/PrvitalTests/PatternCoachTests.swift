import XCTest
@testable import Prvital

final class PatternCoachTests: XCTestCase {

    private func stats(count: Int = 100, cv: Double = 0.25) -> PeriodStatistics {
        var s = PeriodStatistics()
        s.readingCount = count
        s.coefficientOfVariation = cv
        return s
    }

    func testLowsArePrioritisedOverHighs() {
        let insights = [
            GlucoseInsight(period: .overnight, kind: .frequentHigh, fraction: 0.3),
            GlucoseInsight(period: .morning, kind: .frequentLow, fraction: 0.15),
        ]
        let tips = PatternCoach.tips(insights: insights, stats: stats())
        XCTAssertEqual(tips.first?.priority, 0)
        XCTAssertTrue(tips.first!.id.contains("frequentLow"))
    }

    func testVariabilityTipWhenSwingyAndNoPeriodPattern() {
        let tips = PatternCoach.tips(insights: [], stats: stats(cv: 0.45))
        XCTAssertTrue(tips.contains { $0.id == "variability" })
    }

    func testSteadyReassuranceWhenNothingFlagged() {
        let tips = PatternCoach.tips(insights: [], stats: stats(cv: 0.20))
        XCTAssertEqual(tips.map(\.id), ["steady"])
    }

    func testCappedAtThreeTips() {
        let insights = DayPeriod.allCases.map {
            GlucoseInsight(period: $0, kind: .frequentHigh, fraction: 0.3)
        }
        let tips = PatternCoach.tips(insights: insights, stats: stats())
        XCTAssertLessThanOrEqual(tips.count, 3)
    }

    func testEveryTipHasActionableDetail() {
        let insights = [GlucoseInsight(period: .afternoon, kind: .frequentLow, fraction: 0.2)]
        let tips = PatternCoach.tips(insights: insights, stats: stats())
        XCTAssertFalse(tips[0].detail.isEmpty)
    }
}
