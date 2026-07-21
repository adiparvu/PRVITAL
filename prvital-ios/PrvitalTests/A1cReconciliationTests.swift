import XCTest
@testable import Prvital

final class A1cReconciliationTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func labDate() -> Date {
        var dc = DateComponents(); dc.year = 2026; dc.month = 6; dc.day = 15
        return cal.date(from: dc)!
    }

    private func offset(_ days: Int, from base: Date) -> Date {
        cal.date(byAdding: .day, value: days, to: base)!
    }

    private func reading(_ mgdL: Double, _ timestamp: Date) -> GlucoseReading {
        GlucoseReading(valueMgdL: mgdL, timestamp: timestamp, source: .manual)
    }

    /// 30 daily readings at 150 mg/dL → mean 150 → GMI 3.31 + 0.02392·150 = 6.898.
    private func steadyReadings(around lab: Date) -> [GlucoseReading] {
        (1...30).map { reading(150, offset(-$0, from: lab)) }
    }

    func testNilWhenLabValueMissing() {
        let labD = labDate()
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 0, timestamp: labD),
            readings: steadyReadings(around: labD), calendar: cal)
        XCTAssertNil(r)
    }

    func testNilWhenNoReadingsInWindow() {
        let labD = labDate()
        // A reading 200 days before the lab is outside the 90-day window.
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 7, timestamp: labD),
            readings: [reading(150, offset(-200, from: labD))], calendar: cal)
        XCTAssertNil(r)
    }

    func testAlignedWhenEstimateMatchesLab() {
        let labD = labDate()
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 6.9, timestamp: labD),
            readings: steadyReadings(around: labD), calendar: cal)!
        XCTAssertEqual(r.estimatedA1c, 6.898, accuracy: 1e-3)
        XCTAssertEqual(r.alignment, .aligned)
    }

    func testLabHigherWhenBloodTestExceedsEstimate() {
        let labD = labDate()
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 7.6, timestamp: labD),
            readings: steadyReadings(around: labD), calendar: cal)!
        XCTAssertEqual(r.alignment, .labHigher)
        XCTAssertGreaterThan(r.gap, 0)
    }

    func testLabLowerWhenBloodTestBelowEstimate() {
        let labD = labDate()
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 6.2, timestamp: labD),
            readings: steadyReadings(around: labD), calendar: cal)!
        XCTAssertEqual(r.alignment, .labLower)
        XCTAssertLessThan(r.gap, 0)
    }

    func testExcludesReadingsAfterLabDate() {
        let labD = labDate()
        var readings = steadyReadings(around: labD)
        readings.append(reading(400, offset(3, from: labD))) // after the draw — must not count
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 6.9, timestamp: labD),
            readings: readings, calendar: cal)!
        XCTAssertEqual(r.readingCount, 30)
        XCTAssertEqual(r.estimatedA1c, 6.898, accuracy: 1e-3)
    }

    func testSparseCoverageIsFlaggedUnreliable() {
        let labD = labDate()
        let r = A1cReconciler.reconcile(
            lab: LabResult(value: 6.9, timestamp: labD),
            readings: steadyReadings(around: labD), calendar: cal)!
        // 30 readings over 90 days is far below the coverage bar.
        XCTAssertFalse(r.estimateReliable)
    }
}
