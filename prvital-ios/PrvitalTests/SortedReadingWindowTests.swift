import XCTest
@testable import Prvital

final class SortedReadingWindowTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Readings every 5 minutes, like a CGM feed.
    private lazy var series: [GlucoseReading] = (0..<200).map { index in
        GlucoseReading(valueMgdL: Double(80 + index % 60),
                       timestamp: base.addingTimeInterval(Double(index) * 300),
                       source: .dexcom,
                       measurementType: .cgm)
    }

    private func time(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    /// The slice must return exactly what the old `filter` did — that is the
    /// whole safety argument for swapping it in.
    func testInclusiveSliceMatchesFilter() {
        for (from, through) in [(0.0, 60.0), (7.5, 42.5), (-100, 20), (900, 1200), (990, 2000)] {
            let lower = time(from), upper = time(through)
            let expected = series.filter { $0.timestamp >= lower && $0.timestamp <= upper }
            let actual = Array(series.readings(from: lower, through: upper))
            XCTAssertEqual(actual.map(\.timestamp), expected.map(\.timestamp),
                           "window \(from)…\(through)")
        }
    }

    func testExclusiveLowerSliceMatchesFilter() {
        for (after, through) in [(0.0, 60.0), (5.0, 5.0), (12.5, 47.5), (995, 1100)] {
            let lower = time(after), upper = time(through)
            let expected = series.filter { $0.timestamp > lower && $0.timestamp <= upper }
            let actual = Array(series.readings(after: lower, through: upper))
            XCTAssertEqual(actual.map(\.timestamp), expected.map(\.timestamp),
                           "window \(after)…\(through)")
        }
    }

    func testWindowEntirelyBeforeOrAfterIsEmpty() {
        XCTAssertTrue(series.readings(from: time(-500), through: time(-100)).isEmpty)
        XCTAssertTrue(series.readings(from: time(5000), through: time(9000)).isEmpty)
    }

    func testInvertedWindowIsEmptyRatherThanACrash() {
        XCTAssertTrue(series.readings(from: time(120), through: time(60)).isEmpty)
    }

    func testEmptySeries() {
        let empty: [GlucoseReading] = []
        XCTAssertTrue(empty.readings(from: time(0), through: time(60)).isEmpty)
        XCTAssertTrue(empty.readings(after: time(0), through: time(60)).isEmpty)
    }

    /// Boundaries are the whole point of a binary search — an off-by-one here
    /// would silently drop the reading right at a meal.
    func testExactBoundariesAreIncluded() {
        let first = series[0].timestamp
        let third = series[2].timestamp
        let inclusive = Array(series.readings(from: first, through: third))
        XCTAssertEqual(inclusive.count, 3)
        XCTAssertEqual(inclusive.first?.timestamp, first)
        XCTAssertEqual(inclusive.last?.timestamp, third)

        let exclusive = Array(series.readings(after: first, through: third))
        XCTAssertEqual(exclusive.count, 2)
        XCTAssertEqual(exclusive.first?.timestamp, series[1].timestamp)
    }

    /// Duplicate timestamps (two sources landing on the same instant) must all
    /// come back, not just the one the search happened to land on.
    func testDuplicateTimestampsAreAllIncluded() {
        let instant = base.addingTimeInterval(600)
        let duplicates = (0..<4).map { _ in
            GlucoseReading(valueMgdL: 120, timestamp: instant, source: .manual, measurementType: .fingerstick)
        }
        let merged = (series + duplicates).sorted { $0.timestamp < $1.timestamp }
        let slice = merged.readings(from: instant, through: instant)
        XCTAssertEqual(slice.count, 5, "4 duplicates plus the CGM sample at the same instant")
    }
}
