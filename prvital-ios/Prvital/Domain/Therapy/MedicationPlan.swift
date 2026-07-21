import Foundation

/// One scheduled medication in the user's plan: what it is, the dose, and the
/// daily times it's meant to be taken. Config-like, so it lives in `Preferences`
/// (Codable) rather than the SwiftData store; the logged doses are the records.
struct MedicationSchedule: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = MedicationKind.other.rawValue
    var amount: Double = 0
    var unitText: String = ""
    /// Daily target times, as minutes from midnight (e.g. 8*60, 20*60).
    var times: [Int] = []
    var remindersEnabled: Bool = true
    var enabled: Bool = true

    var kind: MedicationKind {
        get { MedicationKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var doseText: String {
        guard amount > 0, !unitText.isEmpty else { return name }
        let n = amount.formatted(.number.precision(.fractionLength(amount == amount.rounded() ? 0 : 2)))
        return "\(n) \(unitText)"
    }

    /// Times sorted ascending, de-duplicated.
    var sortedTimes: [Int] { Array(Set(times)).sorted() }
}

/// The user's whole medication plan.
struct MedicationPlan: Codable, Equatable, Sendable {
    var schedules: [MedicationSchedule] = []

    static let empty = MedicationPlan()

    var activeSchedules: [MedicationSchedule] { schedules.filter(\.enabled) }
    var hasReminders: Bool { activeSchedules.contains { $0.remindersEnabled && !$0.times.isEmpty } }
}

/// One slot in today's take-checklist.
struct MedicationSlot: Identifiable, Equatable, Sendable {
    let scheduleID: UUID
    let name: String
    let kind: MedicationKind
    let doseText: String
    let minute: Int
    var taken: Bool

    var id: String { "\(scheduleID)-\(minute)" }
}

/// Pure schedule → slot / adherence logic.
enum MedicationAdherence {
    /// Today's slots across all active schedules, marked taken. A schedule's
    /// slots are filled in time order by how many doses were logged for it today:
    /// one dose ticks the earliest open slot, a second ticks the next, and so on.
    static func todaySlots(
        plan: MedicationPlan,
        doses: [MedicationDose],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [MedicationSlot] {
        let startOfDay = calendar.startOfDay(for: now)
        var slots: [MedicationSlot] = []
        for schedule in plan.activeSchedules where !schedule.times.isEmpty {
            let takenToday = doses.filter {
                $0.scheduleID == schedule.id.uuidString && $0.timestamp >= startOfDay
            }.count
            for (index, minute) in schedule.sortedTimes.enumerated() {
                slots.append(MedicationSlot(
                    scheduleID: schedule.id, name: schedule.name, kind: schedule.kind,
                    doseText: schedule.doseText, minute: minute, taken: index < takenToday))
            }
        }
        return slots.sorted { $0.minute < $1.minute }
    }

    struct Summary: Equatable, Sendable {
        var expected: Int
        var taken: Int
        var fraction: Double     // 0…1, clamped
        var hasPlan: Bool
    }

    /// Adherence over `[start, now]`: expected scheduled slots vs doses logged.
    static func summary(
        plan: MedicationPlan,
        doses: [MedicationDose],
        start: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let active = plan.activeSchedules.filter { !$0.times.isEmpty }
        guard !active.isEmpty else { return Summary(expected: 0, taken: 0, fraction: 0, hasPlan: false) }

        var expected = 0
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: now)
        while day <= lastDay {
            for schedule in active {
                for minute in schedule.sortedTimes {
                    let slot = day.addingTimeInterval(TimeInterval(minute) * 60)
                    if slot >= start && slot <= now { expected += 1 }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let taken = doses.filter { $0.timestamp >= start && $0.timestamp <= now }.count
        let fraction = expected > 0 ? min(1.0, Double(taken) / Double(expected)) : 0
        return Summary(expected: expected, taken: min(taken, expected), fraction: fraction, hasPlan: true)
    }
}
