import XCTest
@testable import Prvital

/// Tests for units, thresholds, statistics and the AGP percentile aggregator.
final class StatisticsAndUnitsTests: XCTestCase {

    func testGlucoseUnitConversionRoundTrips() {
        XCTAssertEqual(GlucoseUnit.mgdL.fromMgdL(120), 120, accuracy: 1e-9)
        XCTAssertEqual(GlucoseUnit.mmolL.fromMgdL(180), 180 / GlucoseUnit.conversionFactor, accuracy: 1e-9)
        XCTAssertEqual(GlucoseUnit.mmolL.toMgdL(10), 10 * GlucoseUnit.conversionFactor, accuracy: 1e-9)
        // Round-trip a display value back to mg/dL.
        let mgdL = GlucoseUnit.mmolL.toMgdL(GlucoseUnit.mmolL.fromMgdL(144))
        XCTAssertEqual(mgdL, 144, accuracy: 1e-9)
    }

    func testThresholdZoneBoundaries() {
        let t = GlucoseThresholds.standard // veryLow 54, target 70...180, high 250
        XCTAssertEqual(t.zone(forMgdL: 40), .veryLow)
        XCTAssertEqual(t.zone(forMgdL: 60), .low)
        XCTAssertEqual(t.zone(forMgdL: 70), .inRange)
        XCTAssertEqual(t.zone(forMgdL: 180), .inRange)
        XCTAssertEqual(t.zone(forMgdL: 200), .high)
        XCTAssertEqual(t.zone(forMgdL: 300), .veryHigh)
    }

    func testStatisticsAveragesAndTimeInRange() {
        let now = Date()
        let values: [Double] = [80, 100, 120, 200, 50] // in-range: 80,100,120 => 3/5
        let readings = values.enumerated().map { index, value in
            GlucoseReading(valueMgdL: value, timestamp: now.addingTimeInterval(Double(-index * 300)), source: .manual)
        }
        let stats = StatisticsEngine.glucose(readings, thresholds: .standard)
        XCTAssertEqual(stats.readingCount, 5)
        XCTAssertEqual(stats.average, values.reduce(0, +) / 5, accuracy: 1e-9)
        XCTAssertEqual(stats.minimum, 50)
        XCTAssertEqual(stats.maximum, 200)
        XCTAssertEqual(stats.timeInRange, 0.6, accuracy: 1e-9)
    }

    func testTimeInTightRangeIsNarrowerThanTimeInRange() {
        let now = Date()
        let values: [Double] = [80, 130, 150, 170, 60]
        let readings = values.enumerated().map { index, value in
            GlucoseReading(valueMgdL: value, timestamp: now.addingTimeInterval(Double(-index * 300)), source: .manual)
        }
        let stats = StatisticsEngine.glucose(readings, thresholds: .standard)
        // Standard TIR (70–180): 80,130,150,170 => 4/5
        XCTAssertEqual(stats.timeInRange, 0.8, accuracy: 1e-9)
        // Tight range (70–140): only 80,130 => 2/5
        XCTAssertEqual(stats.timeInTightRange, 0.4, accuracy: 1e-9)
    }

    func testTightRangeBoundsAreInclusive() {
        let now = Date()
        let values: [Double] = [70, 140, 69, 141] // 70 & 140 inside; 69 & 141 outside
        let readings = values.enumerated().map { index, value in
            GlucoseReading(valueMgdL: value, timestamp: now.addingTimeInterval(Double(-index * 300)), source: .manual)
        }
        let stats = StatisticsEngine.glucose(readings, thresholds: .standard)
        XCTAssertEqual(stats.timeInTightRange, 0.5, accuracy: 1e-9)
    }

    func testStatisticsEmptyIsSafe() {
        let stats = StatisticsEngine.glucose([], thresholds: .standard)
        XCTAssertFalse(stats.hasGlucose)
        XCTAssertEqual(stats.readingCount, 0)
    }

    func testAGPPercentileInterpolation() {
        let sorted = [10.0, 20, 30, 40, 50]
        XCTAssertEqual(AGPAggregator.percentile(sorted, 0.0), 10, accuracy: 1e-9)
        XCTAssertEqual(AGPAggregator.percentile(sorted, 0.5), 30, accuracy: 1e-9)
        XCTAssertEqual(AGPAggregator.percentile(sorted, 1.0), 50, accuracy: 1e-9)
        XCTAssertEqual(AGPAggregator.percentile([42], 0.9), 42, accuracy: 1e-9)
        XCTAssertEqual(AGPAggregator.percentile([], 0.5), 0, accuracy: 1e-9)
    }

    func testAGPBucketsGroupByTimeOfDay() {
        let calendar = Calendar(identifier: .gregorian)
        // Two readings at ~08:00 on different days should land in one hourly bucket.
        var comps = DateComponents(); comps.year = 2024; comps.month = 6; comps.hour = 8; comps.minute = 15
        comps.day = 1
        let d1 = calendar.date(from: comps)!
        comps.day = 2
        let d2 = calendar.date(from: comps)!
        let readings = [
            GlucoseReading(valueMgdL: 100, timestamp: d1, source: .manual),
            GlucoseReading(valueMgdL: 140, timestamp: d2, source: .manual),
        ]
        let buckets = AGPAggregator.buckets(readings, binMinutes: 60, calendar: calendar)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.p50 ?? 0, 120, accuracy: 1e-9) // median of 100,140
    }
}
