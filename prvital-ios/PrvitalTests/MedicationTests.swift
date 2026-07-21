import XCTest
@testable import Prvital

final class MedicationTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func at(hour: Int, minute: Int = 0) -> Date {
        var dc = DateComponents()
        dc.year = 2026; dc.month = 6; dc.day = 15; dc.hour = hour; dc.minute = minute
        return cal.date(from: dc)!
    }

    private func schedule(times: [Int]) -> MedicationSchedule {
        MedicationSchedule(id: UUID(), name: "Metformin", kindRaw: MedicationKind.metformin.rawValue,
                           amount: 500, unitText: "mg", times: times)
    }

    private func dose(_ sched: MedicationSchedule, at date: Date) -> MedicationDose {
        MedicationDose(name: sched.name, kind: sched.kind, amount: sched.amount,
                       unitText: sched.unitText, timestamp: date, scheduleID: sched.id.uuidString)
    }

    // MARK: Today slots

    func testTodaySlotsFillEarliestFirst() {
        let sched = schedule(times: [8 * 60, 20 * 60])
        let plan = MedicationPlan(schedules: [sched])
        let doses = [dose(sched, at: at(hour: 9))]  // one dose taken this morning

        let slots = MedicationAdherence.todaySlots(plan: plan, doses: doses, now: at(hour: 12), calendar: cal)
        XCTAssertEqual(slots.count, 2)
        XCTAssertTrue(slots[0].taken, "the 08:00 slot should be marked taken")
        XCTAssertFalse(slots[1].taken, "the 20:00 slot should still be open")
    }

    func testInactiveSchedulesExcluded() {
        var sched = schedule(times: [8 * 60])
        sched.enabled = false
        let plan = MedicationPlan(schedules: [sched])
        let slots = MedicationAdherence.todaySlots(plan: plan, doses: [], now: at(hour: 12), calendar: cal)
        XCTAssertTrue(slots.isEmpty)
    }

    // MARK: Adherence summary

    func testAdherenceFractionOverOneDay() {
        let sched = schedule(times: [8 * 60, 20 * 60])
        let plan = MedicationPlan(schedules: [sched])
        let doses = [dose(sched, at: at(hour: 9))]

        // Now is 21:00, so both scheduled slots today are due; one was taken.
        let summary = MedicationAdherence.summary(
            plan: plan, doses: doses,
            start: cal.startOfDay(for: at(hour: 0)), now: at(hour: 21), calendar: cal)
        XCTAssertTrue(summary.hasPlan)
        XCTAssertEqual(summary.expected, 2)
        XCTAssertEqual(summary.taken, 1)
        XCTAssertEqual(summary.fraction, 0.5, accuracy: 0.0001)
    }

    func testFutureSlotsNotCountedAsExpected() {
        let sched = schedule(times: [8 * 60, 20 * 60])
        let plan = MedicationPlan(schedules: [sched])
        // Now is 12:00 — only the 08:00 slot has come due.
        let summary = MedicationAdherence.summary(
            plan: plan, doses: [], start: cal.startOfDay(for: at(hour: 0)), now: at(hour: 12), calendar: cal)
        XCTAssertEqual(summary.expected, 1)
        XCTAssertEqual(summary.taken, 0)
    }

    func testNoPlanReportsNoPlan() {
        let summary = MedicationAdherence.summary(
            plan: .empty, doses: [], start: at(hour: 0), now: at(hour: 23), calendar: cal)
        XCTAssertFalse(summary.hasPlan)
        XCTAssertEqual(summary.expected, 0)
    }

    func testDoseTextFormatting() {
        XCTAssertEqual(schedule(times: []).doseText, "500 mg")
        XCTAssertEqual(MedicationSchedule(name: "Vitamin D").doseText, "Vitamin D")
    }
}
