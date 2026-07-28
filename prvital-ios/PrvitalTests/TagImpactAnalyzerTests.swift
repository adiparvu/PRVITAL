import XCTest
@testable import Prvital

final class TagImpactAnalyzerTests: XCTestCase {

    private let calendar = Calendar.current
    private var thresholds: GlucoseThresholds { GlucoseThresholds() }

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        return calendar.date(byAdding: .hour, value: offset * 24 + hour, to: base)!
    }

    private func reading(_ mgdL: Double, day offset: Int, hour: Int = 12,
                         tags: [ObservationTag] = []) -> GlucoseReading {
        let reading = GlucoseReading(valueMgdL: mgdL, timestamp: day(offset, hour: hour), source: .manual)
        reading.tags = tags
        return reading
    }

    func testStressDaysCompareAgainstOthers() {
        // Days 0/1 tagged stress via observations, all readings high (200);
        // days 2/3 untagged, all readings in range (110).
        let notes = [ObservationEntry(tags: [.stress], timestamp: day(0)),
                     ObservationEntry(tags: [.stress], timestamp: day(1))]
        let readings = [reading(200, day: 0), reading(200, day: 1),
                        reading(110, day: 2), reading(110, day: 3)]
        let impacts = TagImpactAnalyzer.analyze(
            readings: readings, carbs: [], observations: notes, thresholds: thresholds)
        XCTAssertEqual(impacts.count, 1)
        let stress = impacts[0]
        XCTAssertEqual(stress.tag, .stress)
        XCTAssertEqual(stress.dayCount, 2)
        XCTAssertEqual(stress.taggedTIR, 0, accuracy: 0.001)
        XCTAssertEqual(stress.untaggedTIR ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(stress.delta ?? 0, -1, accuracy: 0.001)
    }

    func testSingleTaggedDayIsNotEnough() {
        let notes = [ObservationEntry(tags: [.sport], timestamp: day(0))]
        let readings = [reading(110, day: 0), reading(110, day: 1)]
        let impacts = TagImpactAnalyzer.analyze(
            readings: readings, carbs: [], observations: notes, thresholds: thresholds)
        XCTAssertTrue(impacts.isEmpty, "one tagged day is an anecdote, not a pattern")
    }

    func testTagsOnReadingsAndMealsCountToo() {
        let meal = CarbEntry(grams: 60, timestamp: day(0))
        meal.tags = [.eatingOut]
        let readings = [reading(190, day: 0), reading(185, day: 1, tags: [.eatingOut]),
                        reading(110, day: 2), reading(112, day: 3)]
        let impacts = TagImpactAnalyzer.analyze(
            readings: readings, carbs: [meal], observations: [], thresholds: thresholds)
        XCTAssertEqual(impacts.first?.tag, .eatingOut)
        XCTAssertEqual(impacts.first?.dayCount, 2)
    }

    func testAllDaysTaggedMeansNoComparison() {
        let notes = [ObservationEntry(tags: [.travel], timestamp: day(0)),
                     ObservationEntry(tags: [.travel], timestamp: day(1))]
        let readings = [reading(110, day: 0), reading(110, day: 1)]
        let impacts = TagImpactAnalyzer.analyze(
            readings: readings, carbs: [], observations: notes, thresholds: thresholds)
        XCTAssertEqual(impacts.count, 1)
        XCTAssertNil(impacts[0].untaggedTIR)
        XCTAssertNil(impacts[0].delta)
    }
}
