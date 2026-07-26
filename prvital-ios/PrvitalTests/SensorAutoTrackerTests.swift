import XCTest
@testable import Prvital

final class SensorAutoTrackerTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private var expiry: Date { start.addingTimeInterval(SensorKind.dexcomG7.lifetime) }

    /// Readings every five minutes from `from` to `to`.
    private func steady(from: Date, to: Date) -> [Date] {
        var dates: [Date] = []
        var t = from
        while t <= to {
            dates.append(t)
            t = t.addingTimeInterval(5 * 60)
        }
        return dates
    }

    func testNotExpiredNeverRestarts() {
        // Day 3 of a G7, with a huge gap in the data — still mid-wear.
        let auto = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start,
            readingDates: [start.addingTimeInterval(3_600), start.addingTimeInterval(2 * 86_400)],
            now: start.addingTimeInterval(3 * 86_400))
        XCTAssertNil(auto)
    }

    func testReplacementGapStartsNextSession() {
        // Steady data until 1 h before expiry, silence, resume 2 h after expiry.
        let resume = expiry.addingTimeInterval(2 * 3_600)
        let dates = steady(from: expiry.addingTimeInterval(-20 * 3_600),
                           to: expiry.addingTimeInterval(-3_600)) + [resume]
        let auto = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: dates,
            now: expiry.addingTimeInterval(3 * 3_600))
        XCTAssertEqual(auto?.kind, .dexcomG7)
        // Backdated by the G7's 30-minute warm-up.
        XCTAssertEqual(auto?.startDate, resume.addingTimeInterval(-30 * 60))
    }

    func testContinuousDataNeverRestarts() {
        // Expired, but the readings never paused — no replacement happened.
        let dates = steady(from: expiry.addingTimeInterval(-20 * 3_600), to: expiry)
        let auto = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: dates,
            now: expiry.addingTimeInterval(600))
        XCTAssertNil(auto)
    }

    func testSilenceWithoutResumeNeverRestarts() {
        // Data just stopped at expiry. Until readings actually resume there is
        // no evidence of a new sensor.
        let dates = steady(from: expiry.addingTimeInterval(-6 * 3_600), to: expiry)
        let auto = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: dates,
            now: expiry.addingTimeInterval(2 * 86_400))
        XCTAssertNil(auto)
    }

    func testGapResumingLongBeforeExpiryDoesNotCount() {
        // A 10-hour dropout resuming 20 h before expiry is an outage mid-wear,
        // not a replacement (the window opens 12 h before expiry).
        let dates = [expiry.addingTimeInterval(-30 * 3_600),
                     expiry.addingTimeInterval(-20 * 3_600)]
        let auto = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: dates,
            now: expiry.addingTimeInterval(3_600))
        XCTAssertNil(auto)
    }

    func testKeepsTheLatestQualifyingGap() {
        // Two qualifying gaps — one resuming 6 h before expiry, one 1 h after.
        // The freshest change wins.
        let earlyResume = expiry.addingTimeInterval(-6 * 3_600)
        let lateResume = expiry.addingTimeInterval(3_600)
        let dates = [expiry.addingTimeInterval(-10 * 3_600), earlyResume,
                     earlyResume.addingTimeInterval(5 * 60), lateResume]
        let auto = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: dates,
            now: expiry.addingTimeInterval(2 * 3_600))
        XCTAssertEqual(auto?.startDate, lateResume.addingTimeInterval(-30 * 60))
    }

    func testGapMustCoverTheWarmup() {
        // A 40-minute pause qualifies for a G7 (30-min warm-up) but not for a
        // Libre 3 (60-min warm-up): swapping a Libre cannot be that quick.
        let libreExpiry = start.addingTimeInterval(SensorKind.freeStyleLibre3.lifetime)
        let dates = [libreExpiry.addingTimeInterval(3_600),
                     libreExpiry.addingTimeInterval(3_600 + 40 * 60)]
        let libre = SensorAutoTracker.evaluateRestart(
            lastKind: .freeStyleLibre3, lastStart: start, readingDates: dates,
            now: libreExpiry.addingTimeInterval(3 * 3_600))
        XCTAssertNil(libre)

        let g7Dates = [expiry.addingTimeInterval(3_600),
                       expiry.addingTimeInterval(3_600 + 40 * 60)]
        let g7 = SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: g7Dates,
            now: expiry.addingTimeInterval(3 * 3_600))
        XCTAssertNotNil(g7)
    }

    func testEmptyOrSingleReadingNeverRestarts() {
        XCTAssertNil(SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start, readingDates: [],
            now: expiry.addingTimeInterval(86_400)))
        XCTAssertNil(SensorAutoTracker.evaluateRestart(
            lastKind: .dexcomG7, lastStart: start,
            readingDates: [expiry.addingTimeInterval(3_600)],
            now: expiry.addingTimeInterval(86_400)))
    }
}
