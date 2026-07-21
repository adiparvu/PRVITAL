import Foundation

/// Persists which achievements have been **earned** and which the user has
/// **seen**. Earned is monotonic — once won, an achievement never disappears,
/// even if recent data dips — so the store unions new unlocks in rather than
/// recomputing membership from scratch. Backed by the shared App Group defaults,
/// like the other lightweight stores.
@MainActor
final class AchievementStore {
    private let defaults: UserDefaults
    private static let earnedKey = "achievements.earned"
    private static let seenKey = "achievements.seen"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard
    }

    /// Every achievement earned so far.
    var earned: Set<AchievementID> {
        Set((defaults.array(forKey: Self.earnedKey) as? [String] ?? [])
            .compactMap(AchievementID.init(rawValue:)))
    }

    /// Achievements the user has already looked at (for the "New" indicator).
    var seen: Set<AchievementID> {
        Set((defaults.array(forKey: Self.seenKey) as? [String] ?? [])
            .compactMap(AchievementID.init(rawValue:)))
    }

    /// Folds the freshly-evaluated unlock set into the earned set and returns the
    /// achievements that are newly earned this call (for celebration).
    @discardableResult
    func record(unlocked: Set<AchievementID>) -> [AchievementID] {
        let before = earned
        let fresh = unlocked.subtracting(before)
        guard !fresh.isEmpty else { return [] }
        let union = before.union(fresh)
        defaults.set(union.map(\.rawValue), forKey: Self.earnedKey)
        // Keep catalogue order for a stable, pleasant reveal order.
        return AchievementID.allCases.filter { fresh.contains($0) }
    }

    /// Count of earned achievements the user hasn't opened the gallery to see yet.
    var unseenCount: Int { earned.subtracting(seen).count }

    /// Marks everything currently earned as seen (called when the gallery opens).
    func markAllSeen() {
        defaults.set(earned.map(\.rawValue), forKey: Self.seenKey)
    }
}
