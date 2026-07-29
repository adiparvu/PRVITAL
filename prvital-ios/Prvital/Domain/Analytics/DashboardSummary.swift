import Foundation

/// The derived state the dashboard renders: current value, its zone, the recent
/// series, and the most recent insulin / meal / activity. Pure — built from
/// fetched arrays so the view stays declarative.
struct DashboardSummary {
    var current: GlucoseReading?
    var recent: [GlucoseReading] = []
    var lastInsulin: InsulinDose?
    var lastMeal: CarbEntry?
    var lastActivity: ActivityEntry?
    var thresholds: GlucoseThresholds = .standard
    var now: Date = Date()

    var zone: GlucoseZone? {
        current.map { thresholds.zone(forMgdL: $0.valueMgdL) }
    }

    /// A reading older than 20 minutes is considered stale for the live tile.
    var isStale: Bool {
        guard let current else { return true }
        return now.timeIntervalSince(current.timestamp) > 20 * 60
    }

    var minutesSinceUpdate: Int? {
        current.map { Int(now.timeIntervalSince($0.timestamp) / 60) }
    }

    /// Short-term rate of change and projection, when a fresh reading and enough
    /// recent points exist. `nil` while the current reading is stale.
    var velocity: GlucoseVelocity? {
        guard !isStale else { return nil }
        return GlucoseTrendAnalyzer.velocity(recent, now: now)
    }

    /// How far back the gauge's hour trail reaches.
    static let trailWindow: TimeInterval = 60 * 60
    /// How far from that instant a reading may sit and still anchor the trail.
    /// Wide enough to absorb a missed CGM reading or two, tight enough that a
    /// gap in the trace draws nothing rather than a trail measured from
    /// somewhere else entirely.
    static let trailTolerance: TimeInterval = 12 * 60

    /// Where glucose stood an hour before the CURRENT reading — the anchor for
    /// the dashboard gauge's hour trail.
    ///
    /// Measured from the reading's own timestamp, not from `now`: with a reading
    /// eight minutes old, "an hour ago" from now would only be 52 minutes of
    /// trace, and the trail would quietly shrink as the reading aged.
    var mgdLAnHourAgo: Double? {
        guard let current, !isStale else { return nil }
        let target = current.timestamp.addingTimeInterval(-Self.trailWindow)
        let nearest = recent.min {
            abs($0.timestamp.timeIntervalSince(target)) < abs($1.timestamp.timeIntervalSince(target))
        }
        guard let nearest,
              nearest.timestamp < current.timestamp,
              abs(nearest.timestamp.timeIntervalSince(target)) <= Self.trailTolerance
        else { return nil }
        return nearest.valueMgdL
    }

    static func make(
        readings: [GlucoseReading],
        insulin: [InsulinDose],
        carbs: [CarbEntry],
        activity: [ActivityEntry],
        thresholds: GlucoseThresholds,
        window: TimeInterval = 3 * 60 * 60,
        now: Date = Date()
    ) -> DashboardSummary {
        let active = readings.filter(\.isActive)
        let cutoff = now.addingTimeInterval(-window)
        return DashboardSummary(
            current: active.max { $0.timestamp < $1.timestamp },
            recent: active.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp },
            lastInsulin: insulin.max { $0.timestamp < $1.timestamp },
            lastMeal: carbs.max { $0.timestamp < $1.timestamp },
            lastActivity: activity.max { $0.startTimestamp < $1.startTimestamp },
            thresholds: thresholds,
            now: now
        )
    }
}
