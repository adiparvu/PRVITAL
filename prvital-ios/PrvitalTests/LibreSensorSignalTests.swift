import XCTest
@testable import Prvital

final class LibreSensorSignalTests: XCTestCase {

    func testReportPendingImportCycle() {
        LibreSensorSignal.report(serial: "TEST-SN-1", activatedAt: Date(timeIntervalSince1970: 1_000_000))
        let pending = LibreSensorSignal.pending()
        XCTAssertEqual(pending?.serial, "TEST-SN-1")
        XCTAssertEqual(pending?.activatedAt, Date(timeIntervalSince1970: 1_000_000))

        // Consuming it clears the pending state…
        LibreSensorSignal.markImported(serial: "TEST-SN-1")
        XCTAssertNil(LibreSensorSignal.pending())

        // …and a NEW serial becomes pending again.
        LibreSensorSignal.report(serial: "TEST-SN-2", activatedAt: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(LibreSensorSignal.pending()?.serial, "TEST-SN-2")
        LibreSensorSignal.markImported(serial: "TEST-SN-2")
    }

    func testInvalidReportsAreIgnored() {
        LibreSensorSignal.report(serial: "", activatedAt: Date(timeIntervalSince1970: 1_000_000))
        LibreSensorSignal.report(serial: "TEST-SN-3", activatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(LibreSensorSignal.pending())
    }
}
