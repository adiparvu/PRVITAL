import XCTest
@testable import Prvital

final class GlucoseDistributionTests: XCTestCase {

    private func reading(_ mgdL: Double) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: Date(timeIntervalSince1970: 1_700_000_000), source: .manual)
    }

    func testBinCountAndPlacement() {
        // 40..300 by 20 -> 13 bins. 50->bin0, 70/75->bin1, 200->bin8.
        let bins = GlucoseDistribution.bins([reading(50), reading(70), reading(75), reading(200)])
        XCTAssertEqual(bins.count, 13)
        XCTAssertEqual(bins[0].count, 1)  // [40,60)
        XCTAssertEqual(bins[1].count, 2)  // [60,80)
        XCTAssertEqual(bins[8].count, 1)  // [200,220)
        XCTAssertEqual(bins[0].lowerMgdL, 40, accuracy: 1e-9)
        XCTAssertEqual(bins[1].midpoint, 70, accuracy: 1e-9)
    }

    func testOutOfRangeValuesClampIntoEndBins() {
        let bins = GlucoseDistribution.bins([reading(20), reading(350)])
        XCTAssertEqual(bins.first?.count, 1)      // 20 clamps into first bin
        XCTAssertEqual(bins.last?.count, 1)       // 350 clamps into last bin
    }

    func testBoundaryValueGoesToUpperBin() {
        // Exactly 60 belongs to [60,80), not [40,60).
        let bins = GlucoseDistribution.bins([reading(60)])
        XCTAssertEqual(bins[0].count, 0)
        XCTAssertEqual(bins[1].count, 1)
    }

    func testEmptyIsEmpty() {
        XCTAssertTrue(GlucoseDistribution.bins([]).isEmpty)
    }

    func testAllReadingsAreCounted() {
        let values = [45.0, 65, 85, 120, 155, 190, 240, 295, 310]
        let bins = GlucoseDistribution.bins(values.map(reading))
        XCTAssertEqual(bins.reduce(0) { $0 + $1.count }, values.count)
    }
}
