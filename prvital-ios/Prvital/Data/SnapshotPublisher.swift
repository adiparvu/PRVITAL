import Foundation
import SwiftData

/// Builds a display-ready `GlucoseSnapshot` from the store and publishes it to
/// the App Group for the widgets and watch. Called after any data change.
@MainActor
final class SnapshotPublisher {
    private let context: ModelContext
    private let preferences: Preferences
    private let registry: SourceRegistry
    private let alerts: GlucoseAlertService

    init(context: ModelContext, preferences: Preferences, registry: SourceRegistry, alerts: GlucoseAlertService) {
        self.context = context
        self.preferences = preferences
        self.registry = registry
        self.alerts = alerts
    }

    func refresh(now: Date = Date()) {
        let unit = preferences.glucoseUnit
        let thresholds = preferences.thresholds

        let readings = fetch(GlucoseReading.self).filter(\.isActive)
        let summary = DashboardSummary.make(
            readings: readings,
            insulin: fetch(InsulinDose.self),
            carbs: fetch(CarbEntry.self),
            activity: fetch(ActivityEntry.self),
            thresholds: thresholds,
            now: now
        )

        var snapshot = GlucoseSnapshot()
        snapshot.unitText = unit.rawValue
        snapshot.targetLowerMgdL = thresholds.targetLower
        snapshot.targetUpperMgdL = thresholds.targetUpper

        var imminent: GlucoseProjection?

        if let current = summary.current {
            let zone = thresholds.zone(forMgdL: current.valueMgdL)
            snapshot.mgdL = current.valueMgdL
            snapshot.valueText = GlucoseFormatting.string(mgdL: current.valueMgdL, unit: unit)
            snapshot.trendSymbol = current.trend?.symbol ?? "arrow.right"
            snapshot.trendLabel = current.trend?.label ?? String(localized: "Stable")
            snapshot.zoneLabel = zone.label
            snapshot.zoneColorHex = Self.hex(for: zone)
            snapshot.sourceName = current.source.displayName
            snapshot.updatedAt = current.timestamp
            snapshot.isStale = summary.isStale

            if !summary.isStale, let velocity = summary.velocity,
               let projection = GlucoseTrendAnalyzer.imminentProjection(
                currentMgdL: current.valueMgdL,
                velocityPerMinute: velocity.mgdLPerMinute,
                thresholds: thresholds
               ) {
                imminent = projection
                snapshot.predictionText = Self.predictionText(projection)
            }
        }

        snapshot.points = summary.recent.map { .init(date: $0.timestamp, mgdL: $0.valueMgdL) }

        if let dose = summary.lastInsulin {
            snapshot.lastInsulinText = String(localized: "\(dose.units.formatted()) U · \(Self.relative(dose.timestamp, now))")
        }
        if let meal = summary.lastMeal {
            snapshot.lastMealText = String(localized: "\(meal.grams.formatted()) g · \(meal.mealType.label)")
        }
        snapshot.recentEntries = Self.recentLines(summary: summary, unit: unit, now: now)

        SharedStore.save(snapshot)
        WatchSessionManager.shared.updateSnapshot(snapshot)
        GlucoseLiveActivityManager.shared.sync(with: snapshot)

        // Reactive glucose alerts, evaluated only on fresh readings.
        alerts.evaluate(
            current: (summary.isStale ? nil : summary.current).map {
                GlucoseAlertEvaluator.Reading(mgdL: $0.valueMgdL, timestamp: $0.timestamp)
            },
            thresholds: thresholds,
            preferences: preferences.alerts,
            unit: unit,
            now: now
        )

        // Predictive early-low warning — before glucose crosses the threshold.
        alerts.evaluatePredictiveLow(
            projection: summary.isStale ? nil : imminent,
            preferences: preferences.alerts,
            now: now
        )

        // Rate-of-change alert on a fresh reading with a measured trend.
        alerts.evaluateRateOfChange(
            current: (summary.isStale ? nil : summary.current).map {
                GlucoseAlertEvaluator.Reading(mgdL: $0.valueMgdL, timestamp: $0.timestamp)
            },
            perMinute: summary.isStale ? nil : summary.velocity?.mgdLPerMinute,
            preferences: preferences.alerts,
            unit: unit,
            now: now
        )

        // Signal-loss alert — measured from the most recent reading's age, even
        // when that reading is now stale (that's exactly the dropout case).
        alerts.evaluateSignalLoss(
            lastReadingAt: summary.current?.timestamp,
            preferences: preferences.alerts,
            now: now
        )
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Localized imminent-projection text, reusing the dashboard's catalog keys.
    private static func predictionText(_ projection: GlucoseProjection) -> String {
        switch projection.kind {
        case .low: return String(localized: "Low predicted in ~\(projection.minutes) min")
        case .high: return String(localized: "High predicted in ~\(projection.minutes) min")
        }
    }

    static func hex(for zone: GlucoseZone) -> UInt {
        switch zone {
        case .veryLow: return 0xD64550
        case .low: return 0xE8730C
        case .inRange: return 0x2FB86B
        case .high: return 0xE0A100
        case .veryHigh: return 0xE8730C
        }
    }

    private static func recentLines(summary: DashboardSummary, unit: GlucoseUnit, now: Date) -> [String] {
        var lines: [String] = []
        if let g = summary.current {
            lines.append("\(GlucoseFormatting.labeled(mgdL: g.valueMgdL, unit: unit)) · \(relative(g.timestamp, now))")
        }
        if let i = summary.lastInsulin {
            lines.append(String(localized: "\(i.units.formatted()) U \(i.insulinType.label.lowercased()) · \(relative(i.timestamp, now))"))
        }
        if let m = summary.lastMeal {
            lines.append(String(localized: "\(m.grams.formatted()) g \(m.mealType.label.lowercased()) · \(relative(m.timestamp, now))"))
        }
        return lines
    }

    private static func relative(_ date: Date, _ now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
