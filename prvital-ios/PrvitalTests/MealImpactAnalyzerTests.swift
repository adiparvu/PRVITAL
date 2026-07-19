import XCTest
@testable import Prvital

final class MealImpactAnalyzerTests: XCTestCase {

    private func reading(_ mgdL: Double, _ offsetMinutes: Double, from base: Date) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: base.addingTimeInterval(offsetMinutes * 60), source: .manual)
    }

    func testBasicExcursion() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = CarbEntry(grams: 60, timestamp: base, mealType: .lunch)
        let readings = [
            reading(100, -5, from: base),   // baseline
            reading(140, 30, from: base),
            reading(180, 60, from: base),   // peak
            reading(150, 90, from: base),
        ]
        let impacts = MealImpactAnalyzer.analyze(meals: [meal], readings: readings)
        let impact = try XCTUnwrap(impacts.first)
        XCTAssertEqual(impact.baselineMgdL, 100, accuracy: 1e-9)
        XCTAssertEqual(impact.peakMgdL, 180, accuracy: 1e-9)
        XCTAssertEqual(impact.deltaMgdL, 80, accuracy: 1e-9)
        XCTAssertEqual(impact.minutesToPeak, 60)
    }

    func testMealWithoutBaselineIsSkipped() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = CarbEntry(grams: 45, timestamp: base, mealType: .dinner)
        // Only post-meal readings; nothing near the meal time for a baseline.
        let readings = [
            reading(160, 30, from: base),
            reading(190, 60, from: base),
        ]
        XCTAssertTrue(MealImpactAnalyzer.analyze(meals: [meal], readings: readings).isEmpty)
    }

    func testMealWithoutPostMealReadingIsSkipped() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = CarbEntry(grams: 45, timestamp: base, mealType: .dinner)
        let readings = [reading(120, -3, from: base)] // baseline only
        XCTAssertTrue(MealImpactAnalyzer.analyze(meals: [meal], readings: readings).isEmpty)
    }

    func testReadingsOutsideWindowAreIgnored() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = CarbEntry(grams: 50, timestamp: base, mealType: .breakfast)
        let readings = [
            reading(110, -4, from: base),   // baseline
            reading(150, 60, from: base),   // in window -> peak
            reading(250, 150, from: base),  // beyond 120-min window, must be ignored
        ]
        let impact = try XCTUnwrap(MealImpactAnalyzer.analyze(meals: [meal], readings: readings).first)
        XCTAssertEqual(impact.peakMgdL, 150, accuracy: 1e-9)
        XCTAssertEqual(impact.minutesToPeak, 60)
    }

    func testZeroCarbMealsAreIgnored() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = CarbEntry(grams: 0, timestamp: base, mealType: .lunch)
        let readings = [reading(100, -3, from: base), reading(150, 45, from: base)]
        XCTAssertTrue(MealImpactAnalyzer.analyze(meals: [meal], readings: readings).isEmpty)
    }

    func testInactiveReadingsAreExcluded() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meal = CarbEntry(grams: 50, timestamp: base, mealType: .lunch)
        let baseline = reading(100, -3, from: base)
        let post = reading(170, 45, from: base)
        post.isActive = false
        // With the only post-meal reading inactive, there is no peak.
        XCTAssertTrue(MealImpactAnalyzer.analyze(meals: [meal], readings: [baseline, post]).isEmpty)
    }

    func testSummaryAverages() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let meals = [
            CarbEntry(grams: 60, timestamp: base, mealType: .lunch),
            CarbEntry(grams: 40, timestamp: base.addingTimeInterval(6 * 3600), mealType: .dinner),
        ]
        var readings: [GlucoseReading] = []
        // Meal 1: 100 -> 180 (rise 80) peak at 60 min.
        readings += [reading(100, -3, from: base), reading(180, 60, from: base)]
        // Meal 2: 120 -> 160 (rise 40) peak at 30 min (offsets relative to base).
        readings += [reading(120, 6 * 60 - 3, from: base), reading(160, 6 * 60 + 30, from: base)]

        let impacts = MealImpactAnalyzer.analyze(meals: meals, readings: readings)
        XCTAssertEqual(impacts.count, 2)
        let summary = MealImpactAnalyzer.summary(impacts)
        XCTAssertEqual(summary?.count, 2)
        XCTAssertEqual(summary?.averageRiseMgdL ?? 0, 60, accuracy: 1e-9)     // (80+40)/2
        XCTAssertEqual(summary?.averageMinutesToPeak ?? 0, 45, accuracy: 1e-9) // (60+30)/2
    }

    func testEmptySummaryIsNil() {
        XCTAssertNil(MealImpactAnalyzer.summary([]))
    }
}
