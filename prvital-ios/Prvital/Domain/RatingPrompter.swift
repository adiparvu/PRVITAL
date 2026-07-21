import Foundation

/// Decides *when* it's respectful to ask for an App Store rating.
///
/// Apple's own guidance (and StoreKit's own throttling) is to ask sparingly and
/// only after the user has had a good experience. This helper counts "positive
/// moments" (e.g. a day where the app is actively used with data) and only lets
/// the app prompt once per app version, after enough of them. The actual prompt
/// is StoreKit's `requestReview`, which the system may still choose to suppress.
@MainActor
enum RatingPrompter {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
    }

    private static let momentsKey = "rating.positiveMoments"
    private static let lastVersionKey = "rating.lastPromptedVersion"

    /// How many positive moments before we consider asking.
    static let momentsThreshold = 5

    /// Records one positive moment. Cheap and idempotent-per-call; call it from a
    /// genuinely good moment, not on every view render.
    static func registerPositiveMoment() {
        let next = defaults.integer(forKey: momentsKey) + 1
        defaults.set(next, forKey: momentsKey)
    }

    /// Returns true at most once per app version, and only after enough positive
    /// moments. Records the prompt so it won't ask again for this version.
    static func consumePromptOpportunity() -> Bool {
        guard defaults.integer(forKey: momentsKey) >= momentsThreshold else { return false }
        let current = AppInfo.version
        guard defaults.string(forKey: lastVersionKey) != current else { return false }
        defaults.set(current, forKey: lastVersionKey)
        return true
    }
}
