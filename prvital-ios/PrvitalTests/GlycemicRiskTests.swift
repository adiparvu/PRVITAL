import XCTest
@testable import Prvital

final class GlycemicRiskTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func readings(_ values: [Double]) -> [GlucoseReading] {
        values.enumerated().map { index, mgdL in
            GlucoseReading(valueMgdL: mgdL,
                           timestamp: base.addingTimeInterval(Double(index) * 300),
                           source: .manual)
        }
    }

    func testTooFewReadingsReturnsNil() {
        XCTAssertNil(GlycemicRiskEngine.compute(readings(Array(repeating: 120, count: 23))))
    }

    /// 112.5 mg/dL is the zero point of Kovatchev's risk scale — a flat series
    /// there carries essentially no risk on either side, and a flat in-range
    /// series has GRI 0.
    func testFlatInRangeSeriesScoresZero() throws {
        let risk = try XCTUnwrap(GlycemicRiskEngine.compute(readings(Array(repeating: 112.5, count: 48))))
        XCTAssertEqual(risk.lbgi, 0, accuracy: 0.05)
        XCTAssertEqual(risk.hbgi, 0, accuracy: 0.05)
        XCTAssertEqual(risk.gri, 0, accuracy: 0.001)
        XCTAssertEqual(risk.mage, 0, accuracy: 0.001)
        XCTAssertEqual(risk.band, .a)
    }

    func testDeepLowsDriveLBGIOnly() throws {
        let risk = try XCTUnwrap(GlycemicRiskEngine.compute(readings(Array(repeating: 45, count: 48))))
        XCTAssertGreaterThan(risk.lbgi, 5, "constant 45 mg/dL is high hypo risk")
        XCTAssertEqual(risk.hbgi, 0, accuracy: 0.001)
        // 100% of time < 54 → hypo component 100 → GRI capped at 100.
        XCTAssertEqual(risk.gri, 100, accuracy: 0.001)
        XCTAssertEqual(risk.band, .e)
    }

    func testHighsDriveHBGIOnly() throws {
        let risk = try XCTUnwrap(GlycemicRiskEngine.compute(readings(Array(repeating: 280, count: 48))))
        XCTAssertGreaterThan(risk.hbgi, 9, "constant 280 mg/dL is high hyper risk")
        XCTAssertEqual(risk.lbgi, 0, accuracy: 0.001)
        // 100% of time > 250 → hyper component 100 → GRI = 100 (capped from 160).
        XCTAssertEqual(risk.gri, 100, accuracy: 0.001)
    }

    func testGRIWeighsHypoHarderThanHyper() throws {
        // 10% of readings very low vs 10% very high, rest flat in range:
        // hypo component 10 → GRI 30; hyper component 10 → GRI 16.
        let lows = try XCTUnwrap(GlycemicRiskEngine.compute(
            readings(Array(repeating: 45, count: 5) + Array(repeating: 112.5, count: 45))))
        let highs = try XCTUnwrap(GlycemicRiskEngine.compute(
            readings(Array(repeating: 280, count: 5) + Array(repeating: 112.5, count: 45))))
        XCTAssertEqual(lows.gri, 30, accuracy: 0.5)
        XCTAssertEqual(highs.gri, 16, accuracy: 0.5)
    }

    /// A clean triangle wave between 100 and 200: every swing is 100 mg/dL,
    /// well above the series SD, so MAGE ≈ 100.
    func testMAGEMeasuresTheSwings() throws {
        var values: [Double] = []
        for _ in 0..<6 {
            values += stride(from: 100.0, through: 200.0, by: 20).map { $0 }
            values += stride(from: 180.0, through: 120.0, by: -20).map { $0 }
        }
        let risk = try XCTUnwrap(GlycemicRiskEngine.compute(readings(values)))
        XCTAssertEqual(risk.mage, 100, accuracy: 12)
    }

    func testMAGEIgnoresJitterOnAClimb() {
        // A steady climb 100 → 220 with ±2 sensor jitter: the climb dominates
        // the SD, so the tiny zig-zags never qualify as excursions.
        let values = (0..<60).map { 100.0 + 2.0 * Double($0) + ($0.isMultiple(of: 2) ? 2.0 : -2.0) }
        XCTAssertEqual(GlycemicRiskEngine.mage(values), 0, accuracy: 0.001)
    }
}
