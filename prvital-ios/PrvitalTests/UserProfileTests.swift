import XCTest
@testable import Prvital

/// Tests for the pure profile helpers added with the expanded profile screen:
/// avatar colour parsing, diagnosis duration, measurement parsing/formatting,
/// the care-team `tel:` sanitiser and the appointment countdown.
final class UserProfileTests: XCTestCase {

    // MARK: - Avatar colour hex

    func testValidHexParses() {
        XCTAssertEqual(ProfileFormatting.hexColorValue("3E8DE3"), 0x3E8DE3)
    }

    func testLeadingHashAndLowercaseAccepted() {
        XCTAssertEqual(ProfileFormatting.hexColorValue("#8b6fe8"), 0x8B6FE8)
    }

    func testSurroundingWhitespaceIgnored() {
        XCTAssertEqual(ProfileFormatting.hexColorValue("  D6568E  "), 0xD6568E)
    }

    func testInvalidHexIsNil() {
        XCTAssertNil(ProfileFormatting.hexColorValue(nil))
        XCTAssertNil(ProfileFormatting.hexColorValue(""))
        XCTAssertNil(ProfileFormatting.hexColorValue("FFF"))          // wrong length
        XCTAssertNil(ProfileFormatting.hexColorValue("12345678"))     // wrong length
        XCTAssertNil(ProfileFormatting.hexColorValue("GGGGGG"))       // not hex
        XCTAssertNil(ProfileFormatting.hexColorValue("#"))
    }

    // MARK: - Years with diabetes

    func testYearsSince() {
        XCTAssertEqual(ProfileFormatting.yearsSince(2019, currentYear: 2026), 7)
        XCTAssertEqual(ProfileFormatting.yearsSince(2026, currentYear: 2026), 0)
    }

    func testFutureYearClampsToZero() {
        XCTAssertEqual(ProfileFormatting.yearsSince(2030, currentYear: 2026), 0)
    }

    func testNilYearIsNil() {
        XCTAssertNil(ProfileFormatting.yearsSince(nil, currentYear: 2026))
    }

    func testDurationLineWording() {
        XCTAssertEqual(ProfileFormatting.durationLine(yearsWithDiabetes: 0), "Diagnosed this year")
        XCTAssertEqual(ProfileFormatting.durationLine(yearsWithDiabetes: 1), "1 year with diabetes")
        XCTAssertEqual(ProfileFormatting.durationLine(yearsWithDiabetes: 7), "7 years with diabetes")
    }

    // MARK: - Weight / height parsing

    func testMeasurementParsesPlainAndDecimal() {
        XCTAssertEqual(ProfileFormatting.measurement(from: "72"), 72)
        XCTAssertEqual(ProfileFormatting.measurement(from: "72.5"), 72.5)
    }

    func testMeasurementAcceptsCommaDecimal() {
        XCTAssertEqual(ProfileFormatting.measurement(from: "72,5"), 72.5)
    }

    func testMeasurementTrimsWhitespace() {
        XCTAssertEqual(ProfileFormatting.measurement(from: "  172 "), 172)
    }

    func testImplausibleMeasurementsAreNil() {
        XCTAssertNil(ProfileFormatting.measurement(from: ""))
        XCTAssertNil(ProfileFormatting.measurement(from: "0"))
        XCTAssertNil(ProfileFormatting.measurement(from: "-5"))
        XCTAssertNil(ProfileFormatting.measurement(from: "1000"))
        XCTAssertNil(ProfileFormatting.measurement(from: "abc"))
    }

    func testMeasurementTextRoundTrips() {
        XCTAssertEqual(ProfileFormatting.measurementText(nil), "")
        XCTAssertEqual(ProfileFormatting.measurementText(72), "72")
        XCTAssertEqual(ProfileFormatting.measurementText(72.5), "72.5")
        // What we render must parse back to the same value.
        XCTAssertEqual(ProfileFormatting.measurement(from: ProfileFormatting.measurementText(68.4)), 68.4)
    }

    // MARK: - Care-team phone dialling

    func testTelURLStripsFormattingAndKeepsPlus() {
        XCTAssertEqual(
            ProfileFormatting.telURL(from: "+40 (721) 555-123")?.absoluteString,
            "tel:+40721555123"
        )
    }

    func testTelURLWithoutPlus() {
        XCTAssertEqual(
            ProfileFormatting.telURL(from: "0721 555 987")?.absoluteString,
            "tel:0721555987"
        )
    }

    func testTelURLWithNoDigitsIsNil() {
        XCTAssertNil(ProfileFormatting.telURL(from: ""))
        XCTAssertNil(ProfileFormatting.telURL(from: "   "))
        XCTAssertNil(ProfileFormatting.telURL(from: "call me"))
    }

    // MARK: - Appointment countdown

    func testDaysUntilUsesCalendarDaysNotElapsedHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let late = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 23))
        )
        let earlyNextDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 1))
        )
        // Only 2 hours apart, but a calendar day boundary is crossed.
        XCTAssertEqual(ProfileFormatting.daysUntil(earlyNextDay, from: late, calendar: calendar), 1)
        XCTAssertEqual(ProfileFormatting.daysUntil(late, from: late, calendar: calendar), 0)
        XCTAssertEqual(ProfileFormatting.daysUntil(late, from: earlyNextDay, calendar: calendar), -1)
    }

    func testAppointmentCountdownWording() {
        XCTAssertEqual(ProfileFormatting.appointmentCountdown(daysAway: 0), "Appointment today")
        XCTAssertEqual(ProfileFormatting.appointmentCountdown(daysAway: 1), "Appointment tomorrow")
        XCTAssertEqual(ProfileFormatting.appointmentCountdown(daysAway: 12), "Appointment in 12 days")
        XCTAssertEqual(ProfileFormatting.appointmentCountdown(daysAway: 30), "Appointment in 30 days")
    }

    func testAppointmentCountdownHiddenOutsideWindow() {
        XCTAssertNil(ProfileFormatting.appointmentCountdown(daysAway: -1))
        XCTAssertNil(ProfileFormatting.appointmentCountdown(daysAway: 31))
    }
}
