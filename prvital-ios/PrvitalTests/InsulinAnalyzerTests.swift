import XCTest
@testable import Prvital

final class InsulinAnalyzerTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func dose(day: Int, _ units: Double, _ type: InsulinType) -> InsulinDose {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 3; dc.day = day; dc.hour = 9
        return InsulinDose(units: units, timestamp: cal.date(from: dc)!, insulinType: type)
    }

    func testBasalBolusSplitAndDailyAverage() {
        let doses = [
            dose(day: 1, 20, .longActing),  // basal
            dose(day: 1, 5, .rapidActing),  // bolus
            dose(day: 2, 20, .longActing),  // basal
            dose(day: 2, 6, .rapidActing),  // bolus
        ]
        let s = InsulinAnalyzer.summary(doses, calendar: cal)
        XCTAssertEqual(s?.totalUnits ?? 0, 51, accuracy: 1e-9)
        XCTAssertEqual(s?.basalUnits ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(s?.bolusUnits ?? 0, 11, accuracy: 1e-9)
        XCTAssertEqual(s?.daysWithDoses, 2)
        XCTAssertEqual(s?.averageDailyUnits ?? 0, 25.5, accuracy: 1e-9)
        XCTAssertEqual(s?.basalFraction ?? 0, 40.0 / 51.0, accuracy: 1e-9)
    }

    func testNonLongActingCountsAsBolus() {
        let doses = [dose(day: 1, 10, .premixed), dose(day: 1, 4, .intermediate)]
        let s = InsulinAnalyzer.summary(doses, calendar: cal)
        XCTAssertEqual(s?.basalUnits ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(s?.bolusUnits ?? 0, 14, accuracy: 1e-9)
    }

    func testEmptyIsNil() {
        XCTAssertNil(InsulinAnalyzer.summary([], calendar: cal))
    }

    func testAllZeroUnitsIsNil() {
        let doses = [dose(day: 1, 0, .rapidActing), dose(day: 2, 0, .longActing)]
        XCTAssertNil(InsulinAnalyzer.summary(doses, calendar: cal))
    }
}
