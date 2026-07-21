import Foundation

/// The recent, data-driven facts the contextual reminder evaluator needs: when
/// the user last logged a reading, a meal (and how many carbs), and a dose.
/// A value type with no persistence knowledge so the evaluator stays pure.
struct ContextualReminderInput: Equatable, Sendable {
    var lastReadingAt: Date?
    var lastMealAt: Date?
    var lastMealCarbs: Double?
    var lastInsulinAt: Date?

    static let empty = ContextualReminderInput()
}

/// Opt-in, tunable settings for the contextual reminders. Both feature switches
/// default off, so nothing schedules until a caller maps them onto an existing
/// user opt-in. The thresholds keep the reminders conservative — they nudge once
/// and only while a nudge is still actionable.
struct ContextualReminderSettings: Equatable, Sendable {
    /// Enables the "no reading in a while" reminder.
    var readingGapEnabled: Bool = false
    /// Enables the meal-driven reminders (carbs-without-bolus, post-meal recheck).
    var mealContextEnabled: Bool = false

    /// How long after the last reading to remind about a gap.
    var readingGapHours: Double = 4

    /// A meal at or above this many carbs is expected to carry a bolus.
    var carbBolusThresholdGrams: Double = 15
    /// Grace period after the meal before nudging about a missing bolus.
    var carbBolusGraceMinutes: Double = 15
    /// Only nudge about a missing bolus while the meal is at most this recent.
    var carbBolusWindowMinutes: Double = 90

    /// A meal at or above this many carbs is worth a post-meal recheck.
    var largeMealThresholdGrams: Double = 60
    /// How long after a large meal to suggest a recheck.
    var largeMealRecheckHours: Double = 2
    /// Never resurface a recheck for a meal older than this.
    var largeMealMaxAgeHours: Double = 6

    /// Reminders never fire sooner than this many seconds from now, so an
    /// already-overdue nudge still lands as a proper notification rather than
    /// instantly.
    var minLeadSeconds: TimeInterval = 60

    static let disabled = ContextualReminderSettings()
}

/// The distinct contextual reminders. The raw value is the stable identifier the
/// scheduler uses (under its own prefix) so a reminder replaces, never stacks.
enum ContextualReminderKind: String, CaseIterable, Sendable {
    case noRecentReading
    case carbsWithoutBolus
    case largeMealRecheck
}

/// A ready-to-schedule reminder: presentation-ready (already-localized) strings
/// plus when it should fire, expressed as a delay from `now`. No notification or
/// persistence types leak in here.
struct ContextualReminder: Equatable, Sendable, Identifiable {
    let kind: ContextualReminderKind
    let title: String
    let body: String
    /// Seconds from the `now` passed to the evaluator (always ≥ 0).
    let fireDelay: TimeInterval

    var id: String { kind.rawValue }
}

/// Pure, deterministic derivation of the data-driven reminders from recent
/// timestamps + settings + `now`. Mirrors `GlucoseAlertEvaluator`: no
/// UserNotifications, no SwiftData — just a function that is fully unit-testable.
///
/// Because the app re-evaluates on every data change and the scheduler cancels
/// the previous batch by identifier, each reminder is naturally single and
/// self-correcting: a new reading pushes the gap reminder out, a logged bolus
/// drops the carbs-without-bolus reminder, a reading after a meal drops the
/// recheck, and so on.
enum ContextualReminderEvaluator {

    /// Evaluates all reminder kinds and returns those currently due.
    static func evaluate(
        input: ContextualReminderInput,
        settings: ContextualReminderSettings,
        now: Date = Date()
    ) -> [ContextualReminder] {
        var reminders: [ContextualReminder] = []
        if let reminder = readingGap(input: input, settings: settings, now: now) {
            reminders.append(reminder)
        }
        if let reminder = carbsWithoutBolus(input: input, settings: settings, now: now) {
            reminders.append(reminder)
        }
        if let reminder = largeMealRecheck(input: input, settings: settings, now: now) {
            reminders.append(reminder)
        }
        return reminders
    }

    // MARK: Reminder rules

    /// "No reading in the last N hours" — scheduled for `lastReading + gap`, so a
    /// fresh reading simply reschedules it further out. Needs a baseline reading;
    /// with none we can't reason about a gap, so we stay quiet.
    private static func readingGap(
        input: ContextualReminderInput,
        settings: ContextualReminderSettings,
        now: Date
    ) -> ContextualReminder? {
        guard settings.readingGapEnabled, let lastReadingAt = input.lastReadingAt else { return nil }

        let gap = max(0, settings.readingGapHours) * 3600
        let fireAt = lastReadingAt.addingTimeInterval(gap)
        let delay = max(settings.minLeadSeconds, fireAt.timeIntervalSince(now))
        let hours = Int(settings.readingGapHours.rounded())

        return ContextualReminder(
            kind: .noRecentReading,
            title: String(localized: "Time for a glucose reading"),
            body: String(localized: "It's been about \(hours)h since your last reading. A quick check keeps your trend complete."),
            fireDelay: delay
        )
    }

    /// "You logged carbs but no insulin" — only for a meal above the carb
    /// threshold, with no bolus at or after it, and only while the meal is still
    /// recent enough to act on. Fires after a short grace period.
    private static func carbsWithoutBolus(
        input: ContextualReminderInput,
        settings: ContextualReminderSettings,
        now: Date
    ) -> ContextualReminder? {
        guard settings.mealContextEnabled,
              let mealAt = input.lastMealAt,
              let carbs = input.lastMealCarbs,
              carbs >= settings.carbBolusThresholdGrams
        else { return nil }

        // A dose at or after the meal counts as the bolus — nothing to nudge.
        if let insulinAt = input.lastInsulinAt, insulinAt >= mealAt { return nil }

        // Stop nudging once the meal is no longer recent.
        let window = max(0, settings.carbBolusWindowMinutes) * 60
        guard now.timeIntervalSince(mealAt) <= window else { return nil }

        let fireAt = mealAt.addingTimeInterval(max(0, settings.carbBolusGraceMinutes) * 60)
        let delay = max(settings.minLeadSeconds, fireAt.timeIntervalSince(now))
        let grams = Int(carbs.rounded())

        return ContextualReminder(
            kind: .carbsWithoutBolus,
            title: String(localized: "Carbs logged without insulin"),
            body: String(localized: "You logged \(grams) g of carbs but no bolus. Add your dose if you meant to."),
            fireDelay: delay
        )
    }

    /// "Recheck after that large meal" — for a meal above the large-meal
    /// threshold with no reading yet after it, scheduled for `mealAt + recheck`.
    /// Suppressed once a post-meal reading exists or the meal grows stale.
    private static func largeMealRecheck(
        input: ContextualReminderInput,
        settings: ContextualReminderSettings,
        now: Date
    ) -> ContextualReminder? {
        guard settings.mealContextEnabled,
              let mealAt = input.lastMealAt,
              let carbs = input.lastMealCarbs,
              carbs >= settings.largeMealThresholdGrams
        else { return nil }

        // A reading at or after the meal means the recheck is already done.
        if let readingAt = input.lastReadingAt, readingAt >= mealAt { return nil }

        // Don't resurface a recheck for a meal that's too old to matter now.
        let maxAge = max(0, settings.largeMealMaxAgeHours) * 3600
        guard now.timeIntervalSince(mealAt) <= maxAge else { return nil }

        let fireAt = mealAt.addingTimeInterval(max(0, settings.largeMealRecheckHours) * 3600)
        let delay = max(settings.minLeadSeconds, fireAt.timeIntervalSince(now))
        let grams = Int(carbs.rounded())

        return ContextualReminder(
            kind: .largeMealRecheck,
            title: String(localized: "Recheck after your meal"),
            body: String(localized: "It's been a while since your \(grams) g meal — a reading now shows how it landed."),
            fireDelay: delay
        )
    }
}
