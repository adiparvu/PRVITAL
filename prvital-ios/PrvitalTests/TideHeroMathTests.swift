import XCTest
@testable import Prvital

/// Geometry of the dashboard's tide-style hero: gauge position, target band,
/// and which wave points earn the peak/trough annotations.
final class TideHeroMathTests: XCTestCase {

    // MARK: Gauge fraction

    func testGaugeFractionSpansTheScale() {
        XCTAssertEqual(TideHeroMath.gaugeFraction(mgdL: 40), 0, accuracy: 1e-9)
        XCTAssertEqual(TideHeroMath.gaugeFraction(mgdL: 250), 1, accuracy: 1e-9)
        XCTAssertEqual(TideHeroMath.gaugeFraction(mgdL: 145), 0.5, accuracy: 1e-9)
    }

    func testGaugeFractionClampsOutOfScaleReadings() {
        XCTAssertEqual(TideHeroMath.gaugeFraction(mgdL: 20), 0, accuracy: 1e-9)
        XCTAssertEqual(TideHeroMath.gaugeFraction(mgdL: 400), 1, accuracy: 1e-9)
    }

    // MARK: Target band

    func testBandFractionsOrderAndPosition() {
        let band = TideHeroMath.bandFractions(lowerMgdL: 70, upperMgdL: 180)
        XCTAssertNotNil(band)
        if let band {
            XCTAssertLessThan(band.lowerBound, band.upperBound)
            XCTAssertEqual(band.lowerBound, (70.0 - 40) / 210, accuracy: 1e-9)
            XCTAssertEqual(band.upperBound, (180.0 - 40) / 210, accuracy: 1e-9)
        }
    }

    func testDegenerateThresholdsProduceNoBand() {
        XCTAssertNil(TideHeroMath.bandFractions(lowerMgdL: 180, upperMgdL: 70))
        XCTAssertNil(TideHeroMath.bandFractions(lowerMgdL: 100, upperMgdL: 100))
    }

    /// Thresholds pinned outside the visible scale collapse to a zero-width
    /// band and must yield nil, not an inverted arc.
    func testBandBeyondScaleCollapsesToNil() {
        XCTAssertNil(TideHeroMath.bandFractions(lowerMgdL: 260, upperMgdL: 300))
    }

    // MARK: Extremes

    private func point(_ minute: Int, _ mgdL: Double) -> TidePoint {
        TidePoint(date: Date(timeIntervalSince1970: Double(minute) * 60), mgdL: mgdL)
    }

    func testExtremesPickTheHighestAndLowestPoints() {
        let points = [point(0, 110), point(5, 180), point(10, 95), point(15, 130)]
        let extremes = TideHeroMath.extremes(of: points)
        XCTAssertEqual(extremes.high, point(5, 180))
        XCTAssertEqual(extremes.low, point(10, 95))
    }

    func testFlatSeriesKeepsOnlyTheHigh() {
        let points = [point(0, 120), point(5, 120), point(10, 120)]
        let extremes = TideHeroMath.extremes(of: points)
        XCTAssertNotNil(extremes.high)
        XCTAssertNil(extremes.low)
    }

    func testTooFewPointsYieldNoExtremes() {
        let extremes = TideHeroMath.extremes(of: [point(0, 100), point(5, 200)])
        XCTAssertNil(extremes.high)
        XCTAssertNil(extremes.low)
        let empty = TideHeroMath.extremes(of: [])
        XCTAssertNil(empty.high)
        XCTAssertNil(empty.low)
    }
}
