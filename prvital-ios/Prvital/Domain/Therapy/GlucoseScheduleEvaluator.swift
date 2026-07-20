import Foundation

/// Whether a scheduled glucose check has been done today, is due, or is still to
/// come.
enum GlucoseSlotState: String, Sendable {
    case done
    case due
    case upcoming
}

/// The evaluated status of one scheduled slot for a given day.
struct GlucoseSlotStatus: Identifiable, Sendable {
    let slot: GlucoseLogSlot
    let state: GlucoseSlotState
    /// The reading time that satisfied the slot, when done.
    let matchedReading: Date?
    var id: UUID { slot.id }
}

/// Pure evaluation of a glucose-logging schedule against the day's readings,
/// deciding for each slot whether it's already logged, overdue, or upcoming.
enum GlucoseScheduleEvaluator {

    /// Evaluates each active slot for the day containing `now`:
    /// - `.done` when a reading exists within ±`windowMinutes` of the slot time,
    /// - `.due` when the slot time (plus the window) has passed with no reading,
    /// - `.upcoming` otherwise.
    static func status(
        schedule: GlucoseSchedule,
        readingTimes: [Date],
        now: Date,
        windowMinutes: Int = 90,
        calendar: Calendar = .current
    ) -> [GlucoseSlotStatus] {
        let startOfDay = calendar.startOfDay(for: now)
        let window = TimeInterval(windowMinutes * 60)
        let todaysReadings = readingTimes.filter { calendar.isDate($0, inSameDayAs: now) }

        return schedule.activeSlots.map { slot in
            let slotDate = startOfDay.addingTimeInterval(TimeInterval(slot.minutesFromMidnight * 60))
            let match = todaysReadings.first { abs($0.timeIntervalSince(slotDate)) <= window }

            let state: GlucoseSlotState
            if let match, match <= now {
                state = .done
            } else if now.timeIntervalSince(slotDate) > window {
                state = .due
            } else {
                state = .upcoming
            }
            return GlucoseSlotStatus(slot: slot, state: state, matchedReading: state == .done ? match : nil)
        }
    }

    /// A quick count of how many slots are done vs. total, for a summary badge.
    static func progress(_ statuses: [GlucoseSlotStatus]) -> (done: Int, total: Int) {
        (statuses.filter { $0.state == .done }.count, statuses.count)
    }
}
