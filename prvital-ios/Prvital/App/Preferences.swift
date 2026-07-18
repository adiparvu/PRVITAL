import Foundation
import Observation

/// User-facing preferences, persisted in the shared App Group defaults so the
/// widgets and watch read the same unit and target range.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
        self.glucoseUnit = Self.readUnit(self.defaults)
        self.thresholds = Self.readThresholds(self.defaults)
        self.reminders = Self.readReminders(self.defaults)
    }

    var glucoseUnit: GlucoseUnit {
        didSet { defaults.set(glucoseUnit.rawValue, forKey: Keys.unit) }
    }

    var thresholds: GlucoseThresholds {
        didSet { if let data = try? JSONEncoder().encode(thresholds) { defaults.set(data, forKey: Keys.thresholds) } }
    }

    var reminders: ReminderPreferences {
        didSet { if let data = try? JSONEncoder().encode(reminders) { defaults.set(data, forKey: Keys.reminders) } }
    }

    /// Quick-add presets (the +1U … +10U row and 20g … 100g row).
    let insulinPresets: [Double] = [1, 2, 4, 6, 8, 10]
    let carbPresets: [Double] = [20, 40, 60, 80, 100]
    let activityDurations: [Int] = [15, 30, 45, 60, 90, 120]

    // MARK: Persistence

    private enum Keys {
        static let unit = "pref.glucoseUnit"
        static let thresholds = "pref.thresholds"
        static let reminders = "pref.reminders"
    }

    private static func readUnit(_ d: UserDefaults) -> GlucoseUnit {
        d.string(forKey: Keys.unit).flatMap(GlucoseUnit.init(rawValue:)) ?? .mgdL
    }
    private static func readThresholds(_ d: UserDefaults) -> GlucoseThresholds {
        guard let data = d.data(forKey: Keys.thresholds),
              let value = try? JSONDecoder().decode(GlucoseThresholds.self, from: data)
        else { return .standard }
        return value
    }
    private static func readReminders(_ d: UserDefaults) -> ReminderPreferences {
        guard let data = d.data(forKey: Keys.reminders),
              let value = try? JSONDecoder().decode(ReminderPreferences.self, from: data)
        else { return .default }
        return value
    }
}

/// Configurable reminder schedule. Times are minutes-from-midnight so they
/// serialise cleanly and stay time-zone-relative to the user's day.
struct ReminderPreferences: Codable, Equatable, Sendable {
    var journalEnabled = false
    var journalTimes: [Int] = [8 * 60, 20 * 60]        // 08:00, 20:00
    var basalEnabled = false
    var basalTime: Int = 22 * 60                        // 22:00
    var mealsEnabled = false
    var mealTimes: [Int] = [8 * 60, 13 * 60, 19 * 60]   // 08:00, 13:00, 19:00
    var hydrationEnabled = false
    var hydrationIntervalHours = 3
    var glucoseCheckEnabled = false
    var glucoseCheckTimes: [Int] = [7 * 60, 12 * 60, 18 * 60, 22 * 60]

    static let `default` = ReminderPreferences()
}
