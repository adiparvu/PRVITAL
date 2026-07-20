import XCTest
@testable import Prvital

final class CareSummaryComposerTests: XCTestCase {

    private func sampleStats() -> PeriodStatistics {
        var stats = PeriodStatistics()
        stats.readingCount = 800
        stats.average = 138
        stats.glucoseManagementIndicator = 6.6
        stats.timeInRange = 0.72
        stats.timeBelowRange = 0.03
        stats.timeAboveRange = 0.25
        stats.timeVeryLow = 0.01
        stats.timeVeryHigh = 0.06
        stats.coefficientOfVariation = 0.34
        stats.hypoEvents = 4
        stats.hyperEvents = 9
        return stats
    }

    func testSummaryContainsKeyMetrics() {
        let input = CareSummaryComposer.Input(
            name: "Ada Lovelace",
            diabetesType: "Type 1",
            therapy: "Injections (MDI)",
            periodLabel: "Last 14 days",
            unit: .mgdL,
            stats: sampleStats(),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let text = CareSummaryComposer.text(input)
        XCTAssertTrue(text.contains("Ada Lovelace"))
        XCTAssertTrue(text.contains("Type 1 · Injections (MDI)"))
        XCTAssertTrue(text.contains("Time in range: 72%"))
        XCTAssertTrue(text.contains("Est. A1c (GMI): 6.6%"))
        XCTAssertTrue(text.contains("138"))
        XCTAssertTrue(text.contains("Low events: 4 · High events: 9"))
        XCTAssertTrue(text.contains("Readings: 800"))
    }

    func testPercentRounding() {
        XCTAssertEqual(CareSummaryComposer.percent(0.723), "72%")
        XCTAssertEqual(CareSummaryComposer.percent(0), "0%")
        XCTAssertEqual(CareSummaryComposer.percent(1), "100%")
    }

    func testEmptyNameFallsBackAndNoData() {
        let input = CareSummaryComposer.Input(
            name: "   ",
            diabetesType: "Type 2",
            therapy: "Diet & exercise",
            periodLabel: "Last 7 days",
            unit: .mgdL,
            stats: PeriodStatistics(),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let text = CareSummaryComposer.text(input)
        XCTAssertTrue(text.contains("Prvital user"))
        XCTAssertTrue(text.contains("No glucose readings"))
    }
}
