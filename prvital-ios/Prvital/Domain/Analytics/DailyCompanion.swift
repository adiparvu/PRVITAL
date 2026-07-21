import Foundation

/// The companion's mood for the day — drives the icon and tint in the view.
enum CompanionMood: String, Sendable {
    case gettingStarted
    case celebrating
    case steady
    case encouraging
}

/// A short, supportive message from the daily companion. Strings are localized
/// here so the view just renders them.
struct CompanionMessage: Equatable, Sendable {
    let mood: CompanionMood
    let headline: String
    let subline: String
}

/// Generates a warm, **non-judgmental** daily message from today's control.
///
/// Pure and deterministic. The tone is deliberately encouraging whatever the
/// numbers say — a tough day gets kindness and a fresh-start nudge, never a
/// scolding — because motivation, not guilt, keeps people logging.
enum DailyCompanion {
    static func message(
        hasGlucose: Bool,
        tirFraction: Double,
        goalFraction: Double,
        currentZone: GlucoseZone?,
        streakDays: Int,
        now: Date = Date()
    ) -> CompanionMessage {
        // Nothing logged yet today.
        guard hasGlucose else {
            return CompanionMessage(
                mood: .gettingStarted,
                headline: greeting(now),
                subline: String(localized: "Ready when you are — a reading or a meal starts your day."))
        }

        let pct = Int((tirFraction * 100).rounded())
        let streakLine = streakDays >= 2
            ? String(localized: " You're on a \(streakDays)-day streak.")
            : ""

        // Meeting the goal — celebrate.
        if tirFraction >= goalFraction && goalFraction > 0 {
            return CompanionMessage(
                mood: .celebrating,
                headline: String(localized: "You're doing great today"),
                subline: String(localized: "\(pct)% in range so far — lovely work.") + streakLine)
        }

        // A gentle nudge if things are off right now, but still kind.
        if currentZone == .veryLow || currentZone == .low {
            return CompanionMessage(
                mood: .encouraging,
                headline: String(localized: "Let's steady things"),
                subline: String(localized: "A little low right now — treat it and you'll be back on track."))
        }
        if currentZone == .veryHigh {
            return CompanionMessage(
                mood: .encouraging,
                headline: String(localized: "One step at a time"),
                subline: String(localized: "Running high — a correction and some water can help."))
        }

        // Solidly in the middle — steady encouragement.
        if tirFraction >= 0.5 {
            return CompanionMessage(
                mood: .steady,
                headline: String(localized: "Nice and steady"),
                subline: String(localized: "\(pct)% in range today. Small steps add up.") + streakLine)
        }

        // A tougher day — fresh-start kindness, no guilt.
        return CompanionMessage(
            mood: .encouraging,
            headline: String(localized: "Every reading is a fresh start"),
            subline: String(localized: "Today's been bumpy, and that's okay — the next one is a new chance."))
    }

    private static func greeting(_ now: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        case 17..<22: return String(localized: "Good evening")
        default: return String(localized: "Hello")
        }
    }
}
