import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

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

        // The live tile / widget needs only the latest reading plus a few hours of
        // recent points — never the whole (possibly 100k-row) history. Bounded,
        // indexed fetches keep this off the main-thread hot path even right after a
        // multi-year import, which is exactly when the old full-store fetch stalled
        // the app and tripped the background watchdog.
        let seriesWindow: TimeInterval = 6 * 60 * 60
        let cutoff = now.addingTimeInterval(-seriesWindow)
        let summary = DashboardSummary(
            current: latestActiveReading(),
            recent: recentActiveReadings(since: cutoff),
            lastInsulin: latestInsulin(),
            lastMeal: latestMeal(),
            lastActivity: latestActivity(),
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
            snapshot.sourceRaw = current.source.rawValue
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

            // Short-horizon trajectory for the widget chart's dashed forecast tail.
            // Uses the same damped projection the Dashboard shows, so the little
            // dashed continuation agrees with the "~X in N min" figure.
            if !summary.isStale, let velocity = summary.velocity {
                let horizonMinutes = 30
                // No `minutesSinceReading` here on purpose: the widget's dashed
                // tail starts AT the last point and ends at `forecastAt` =
                // reading + horizon, so the displacement must cover exactly the
                // horizon from the reading, not from wall-clock now.
                let forecast = GlucoseForecast.project(
                    currentMgdL: current.valueMgdL,
                    velocityMgdLPerMin: velocity.mgdLPerMinute,
                    sigmaMgdL: velocity.sigmaMgdL,
                    slopeSEPerMinute: velocity.slopeSEPerMinute,
                    horizonMinutes: horizonMinutes)
                // Only worth a dashed tail when the trajectory actually moves; a
                // near-flat projection would just be visual noise on the sparkline.
                if abs(forecast.projectedMgdL - current.valueMgdL) >= 5 {
                    snapshot.forecastMgdL = forecast.projectedMgdL
                    snapshot.forecastAt = current.timestamp.addingTimeInterval(Double(horizonMinutes) * 60)
                    snapshot.forecastLowMgdL = forecast.lowMgdL
                    snapshot.forecastHighMgdL = forecast.highMgdL
                }
            }
        }

        snapshot.points = summary.recent.map { .init(date: $0.timestamp, mgdL: $0.valueMgdL) }

        // Today's headline figures for the large widgets: time-in-range and the
        // average, over today's active readings (a bounded, indexed fetch).
        let todayStart = Calendar.current.startOfDay(for: now)
        let today = recentActiveReadings(since: todayStart).map(\.valueMgdL)
        if !today.isEmpty {
            let inRange = today.filter {
                $0 >= thresholds.targetLower && $0 <= thresholds.targetUpper
            }.count
            let tir = Double(inRange) / Double(today.count) * 100
            snapshot.todayTIRText = "\(Int(tir.rounded()))%"
            let average = today.reduce(0, +) / Double(today.count)
            snapshot.todayAverageText = GlucoseFormatting.string(mgdL: average, unit: unit)
        }

        if let dose = summary.lastInsulin {
            snapshot.lastInsulinText = String(localized: "\(dose.units.formatted()) U · \(Self.relative(dose.timestamp, now))")
        }
        if let meal = summary.lastMeal {
            snapshot.lastMealText = String(localized: "\(meal.grams.formatted()) g · \(meal.mealType.label)")
        }

        // Insulin- and carbs-on-board for the Live Activity / Dynamic Island.
        let bolus = preferences.bolusParameters
        if bolus.isValid {
            let iob = InsulinMath.activeInsulin(doses: recentInsulinDoses(now: now), at: now, parameters: bolus)
            if iob >= 0.05 {
                snapshot.iobText = String(localized: "\(iob.formatted(.number.precision(.fractionLength(1)))) U")
            }
        }
        let cob = CarbMath.carbsOnBoard(entries: recentCarbEntries(now: now), at: now)
        if cob >= 0.5 {
            snapshot.cobText = String(localized: "\(cob.formatted(.number.precision(.fractionLength(0)))) g")
        }

        snapshot.recentEntries = Self.recentLines(summary: summary, unit: unit, now: now)

        // Reload the widgets whenever the published snapshot actually changed.
        // Gating on the reading's value/time alone left every other widget field
        // stale on the Home Screen — IOB after a bolus, COB after a meal, today's
        // TIR/average, the forecast tail — until the *next* CGM reading happened
        // to arrive. Equality still gates the no-change case (most quiet polls),
        // so the reload cadence stays at "something visibly changed" — roughly
        // CGM/logging cadence, well within WidgetKit's budget.
        let previous = SharedStore.load()
        // Rewrite the App Group file only when the snapshot actually changed —
        // an identical snapshot re-serialised to disk every refresh was pure churn.
        if snapshot != previous {
            SharedStore.save(snapshot)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        WatchSessionManager.shared.updateSnapshot(snapshot)
        GlucoseLiveActivityManager.shared.sync(with: snapshot)

        // The sensor link came back after a gap: a fresh reading where the last
        // published one had gone stale. Announced once, right after the sync so
        // it takes the Island from the live reading rather than the other way
        // round. `previous.updatedAt != .distantPast` keeps a first-ever reading
        // from reading as a "reconnection".
        if previous.isStale, !snapshot.isStale, previous.updatedAt != .distantPast {
            GlucoseLiveActivityManager.shared.presentSensorReconnected(sourceName: snapshot.sourceName)
        }

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

    /// Forces a widget timeline reload, bypassing the save throttle. Called once on
    /// launch so an upgrading install repopulates its widgets from the new App
    /// Group file store right away instead of waiting on the reload budget.
    func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// The single most recent *active* reading, regardless of age — so the widget
    /// keeps showing the last known value (dimmed when stale) after an import of
    /// historical data, instead of falling back to "—".
    private func latestActiveReading() -> GlucoseReading? {
        var descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        if let active = (try? context.fetch(descriptor))?.first { return active }
        // Fallback: nothing is flagged active (e.g. every reading in the store was
        // marked superseded by conflict resolution). The journal clearly has data,
        // so show the most recent reading anyway instead of publishing a blank
        // snapshot that leaves the widget on "No data".
        var any = FetchDescriptor<GlucoseReading>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        any.fetchLimit = 1
        return (try? context.fetch(any))?.first
    }

    /// Active readings within the recent window, ascending — the mini-series and
    /// velocity input. Bounded by the indexed timestamp, so it stays cheap.
    private func recentActiveReadings(since cutoff: Date) -> [GlucoseReading] {
        let descriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func latestInsulin() -> InsulinDose? {
        var descriptor = FetchDescriptor<InsulinDose>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func latestMeal() -> CarbEntry? {
        var descriptor = FetchDescriptor<CarbEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func latestActivity() -> ActivityEntry? {
        var descriptor = FetchDescriptor<ActivityEntry>(
            sortBy: [SortDescriptor(\.startTimestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Insulin doses within one duration-of-action of now — the set that can still
    /// contribute insulin-on-board.
    private func recentInsulinDoses(now: Date) -> [InsulinDose] {
        let cutoff = now.addingTimeInterval(-preferences.bolusParameters.durationHours * 3600)
        let descriptor = FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= cutoff && $0.timestamp <= now })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Carb entries within the last few hours — the set that can still contribute
    /// carbs-on-board.
    private func recentCarbEntries(now: Date) -> [CarbEntry] {
        let cutoff = now.addingTimeInterval(-4 * 3600)
        let descriptor = FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= cutoff && $0.timestamp <= now })
        return (try? context.fetch(descriptor)) ?? []
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

    /// Built once — formatter construction is expensive, and this ran on every
    /// snapshot refresh. Safe as a static: the publisher only runs on the main
    /// actor, and the locale changing mid-session recreates the process anyway.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func relative(_ date: Date, _ now: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
