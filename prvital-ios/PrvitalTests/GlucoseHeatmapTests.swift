import XCTest
@testable import Prvital

final class GlucoseHeatmapTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(day: Int, hour: Int) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 6; dc.day = day; dc.hour = hour
        return cal.date(from: dc)!
    }

    func testAveragesBucketByWeekdayAndBlock() {
        // 2026-06-15 is a Monday (weekday 2 → col 1). Two morning readings (hour 8
        // → block 2 with 3-hour blocks) average to 130.
        let readings = [
            GlucoseReading(valueMgdL: 120, timestamp: date(day: 15, hour: 8), source: .dexcom),
            GlucoseReading(valueMgdL: 140, timestamp: date(day: 15, hour: 8), source: .dexcom),
        ]
        let heatmap = GlucoseHeatmap.build(readings, blocksPerDay: 8, calendar: cal)
        XCTAssertEqual(heatmap.blocksPerDay, 8)
        XCTAssertEqual(heatmap.averages[2][1] ?? 0, 130, accuracy: 1e-6)
        XCTAssertTrue(heatmap.hasData)
        // An empty bucket stays nil.
        XCTAssertNil(heatmap.averages[0][0])
    }

    func testInactiveReadingsIgnored() {
        let losing = GlucoseReading(valueMgdL: 40, timestamp: date(day: 15, hour: 8), source: .dexcom)
        losing.isActive = false
        let heatmap = GlucoseHeatmap.build([losing], calendar: cal)
        XCTAssertFalse(heatmap.hasData)
    }

    func testEmptyInput() {
        let heatmap = GlucoseHeatmap.build([], calendar: cal)
        XCTAssertFalse(heatmap.hasData)
    }
}
