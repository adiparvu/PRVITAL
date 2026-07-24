import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the glucose **Live Activity** from the app, driven
/// entirely by the published `GlucoseSnapshot`: while there is a fresh reading
/// the activity is live and kept in sync; when the reading goes stale or absent
/// it ends. No user toggle needed — it follows the data.
///
/// The same activity also carries the momentary presentations — a logged dose or
/// meal, a countdown, a critical alert. Those are pushed with the `present…`
/// calls and **hold** the Island for a short window, after which the live
/// reading takes it back. One activity re-skinned, so nothing ever stacks.
@MainActor
final class GlucoseLiveActivityManager {
    static let shared = GlucoseLiveActivityManager()
    private init() {}

    #if canImport(ActivityKit) && os(iOS)
    private let store = LiveActivityStore()
    /// The most recent snapshot, so a momentary presentation can be built on top
    /// of the real reading (and so the reading can be restored afterwards).
    private var lastSnapshot: GlucoseSnapshot?
    /// While this is in the future, `sync` leaves the Island alone — a logged
    /// action, a countdown or an alert owns it.
    private var holdUntil: Date?
    /// The follow-up transition (confirmation → countdown → live reading), kept
    /// so a newer presentation cancels a stale one.
    private var transition: Task<Void, Never>?

    // MARK: - Live reading

    func sync(with snapshot: GlucoseSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let hasFreshReading = snapshot.updatedAt != .distantPast && !snapshot.isStale
        guard hasFreshReading else { end(); return }

        lastSnapshot = snapshot

        // A momentary presentation owns the Island until its hold expires.
        if let holdUntil, holdUntil > Date() { return }

        push(glucoseState(from: snapshot), staleDate: staleDate(for: snapshot))
    }

    func end() {
        transition?.cancel()
        transition = nil
        holdUntil = nil
        let store = self.store
        Task { await store.finish() }
    }

    // MARK: - Momentary presentations

    /// "Insulin logged — 4 units", then it hands over to the active-insulin
    /// countdown before the live reading takes the Island back.
    func presentInsulinLogged(units: Double, clearsAt: Date, now: Date = Date()) {
        guard var state = baseState() else { return }
        let unitsText = units.formatted(.number.precision(.fractionLength(units < 10 ? 1 : 0)))
        state.kind = .insulinLogged
        state.stateColorHex = LiveActivityPresentation.colorHex(for: .insulinLogged, glucoseState: state.glucoseState)
        state.iconName = LiveActivityPresentation.iconName(for: .insulinLogged, glucoseState: state.glucoseState)
        state.eventCompactText = "\(unitsText)U"
        state.eventTitle = String(localized: "Insulin logged")
        state.eventDetail = "\(unitsText) " + String(localized: "units")
        state.eventCaption = String(localized: "The dose has been recorded.")
        state.progressStart = now
        state.progressEnd = now.addingTimeInterval(Self.confirmationSeconds)

        present(state, holdFor: Self.confirmationSeconds, then: .insulinOnBoard(clearsAt: clearsAt))
    }

    /// "Meal logged — 45 g of carbs".
    func presentMealLogged(grams: Double, now: Date = Date()) {
        guard var state = baseState() else { return }
        let gramsText = grams.formatted(.number.precision(.fractionLength(0)))
        state.kind = .mealLogged
        state.stateColorHex = LiveActivityPresentation.colorHex(for: .mealLogged, glucoseState: state.glucoseState)
        state.iconName = LiveActivityPresentation.iconName(for: .mealLogged, glucoseState: state.glucoseState)
        state.eventCompactText = "\(gramsText)g"
        state.eventTitle = String(localized: "Meal logged")
        state.eventDetail = "\(gramsText) g " + String(localized: "of carbs")
        state.eventCaption = String(localized: "The carbs have been added.")
        state.progressStart = now
        state.progressEnd = now.addingTimeInterval(Self.confirmationSeconds)

        present(state, holdFor: Self.confirmationSeconds)
    }

    /// "Active insulin — 2h 45m", the bar filling as the dose decays to zero.
    func presentInsulinOnBoard(clearsAt: Date, now: Date = Date()) {
        guard var state = baseState(), clearsAt > now else { return }
        state.kind = .insulinOnBoard
        state.stateColorHex = LiveActivityPresentation.colorHex(for: .insulinOnBoard, glucoseState: state.glucoseState)
        state.iconName = LiveActivityPresentation.iconName(for: .insulinOnBoard, glucoseState: state.glucoseState)
        state.eventCompactText = Self.clock(until: clearsAt, from: now)
        state.eventTitle = String(localized: "Active insulin")
        state.eventDetail = Self.duration(until: clearsAt, from: now)
        state.eventCaption = String(localized: "Time left until zero.")
        state.progressStart = now
        state.progressEnd = clearsAt

        present(state, holdFor: Self.countdownSeconds)
    }

    /// "Next meal in — 1h 15m".
    func presentMealCountdown(dueAt: Date, now: Date = Date()) {
        guard var state = baseState(), dueAt > now else { return }
        state.kind = .mealCountdown
        state.stateColorHex = LiveActivityPresentation.colorHex(for: .mealCountdown, glucoseState: state.glucoseState)
        state.iconName = LiveActivityPresentation.iconName(for: .mealCountdown, glucoseState: state.glucoseState)
        state.eventCompactText = Self.clock(until: dueAt, from: now)
        state.eventTitle = String(localized: "Next meal in")
        state.eventDetail = Self.duration(until: dueAt, from: now)
        state.eventCaption = String(localized: "Your next meal.")
        state.progressStart = now
        state.progressEnd = dueAt

        present(state, holdFor: Self.countdownSeconds)
    }

    /// The loud moment: a critical low or high, with what to do about it.
    func presentGlucoseAlert(isLow: Bool) {
        guard var state = baseState() else { return }
        let kind: LiveActivityKind = isLow ? .alertLow : .alertHigh
        state.kind = kind
        state.glucoseState = .alert
        state.stateColorHex = LiveActivityPresentation.colorHex(for: kind, glucoseState: .alert)
        state.iconName = LiveActivityPresentation.iconName(for: kind, glucoseState: .alert)
        state.eventCompactText = nil
        state.eventTitle = isLow ? String(localized: "Glucose is too low!") : String(localized: "Glucose is too high!")
        let level = isLow ? String(localized: "Low") : String(localized: "High")
        state.eventDetail = "\(level): \(state.valueText) \(state.unitText)"
        state.eventCaption = isLow
            ? String(localized: "Have 15 g of fast carbs")
            : String(localized: "Check and correct")
        state.progressStart = nil
        state.progressEnd = nil

        present(state, holdFor: Self.alertSeconds)
    }

    /// "Sensor reconnected — Dexcom G7 connected".
    func presentSensorReconnected(sourceName: String) {
        guard var state = baseState() else { return }
        state.kind = .sensorReconnected
        state.stateColorHex = LiveActivityPresentation.colorHex(for: .sensorReconnected, glucoseState: state.glucoseState)
        state.iconName = LiveActivityPresentation.iconName(for: .sensorReconnected, glucoseState: state.glucoseState)
        state.eventCompactText = nil
        state.eventTitle = String(localized: "Sensor reconnected")
        state.eventDetail = String(localized: "Sensor reconnected")
        state.eventCaption = "\(sourceName) · " + String(localized: "Connected")
        state.progressStart = nil
        state.progressEnd = nil

        present(state, holdFor: Self.confirmationSeconds)
    }

    /// "Sensor battery: 20% — replace the sensor soon".
    func presentSensorBattery(percent: Int) {
        guard var state = baseState() else { return }
        state.kind = .sensorBattery
        state.stateColorHex = LiveActivityPresentation.colorHex(for: .sensorBattery, glucoseState: state.glucoseState)
        state.iconName = LiveActivityPresentation.iconName(for: .sensorBattery, glucoseState: state.glucoseState)
        state.eventCompactText = "\(percent)%"
        state.eventTitle = String(localized: "Sensor battery")
        state.eventDetail = String(localized: "Sensor battery") + ": \(percent)%"
        state.eventCaption = String(localized: "Replace the sensor soon")
        state.progressStart = nil
        state.progressEnd = nil

        present(state, holdFor: Self.batterySeconds)
    }

    // MARK: - Plumbing

    /// How long each family owns the Island before the live reading returns.
    private static let confirmationSeconds: TimeInterval = 8
    private static let countdownSeconds: TimeInterval = 60
    private static let alertSeconds: TimeInterval = 120
    private static let batterySeconds: TimeInterval = 15

    /// What takes the Island once a momentary presentation's hold expires. A
    /// plain `Sendable` value rather than a closure, so nothing non-sendable is
    /// captured by the transition `Task` under Swift 6 strict concurrency.
    private enum FollowUp: Sendable {
        /// Hand the Island back to the live reading.
        case liveReading
        /// Confirmation → the active-insulin countdown.
        case insulinOnBoard(clearsAt: Date)
    }

    /// Pushes a momentary presentation, holds the Island for `holdFor`, then runs
    /// the follow-up — by default handing the Island back to the live reading.
    private func present(
        _ state: GlucoseActivityAttributes.ContentState,
        holdFor seconds: TimeInterval,
        then next: FollowUp = .liveReading
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let snapshot = lastSnapshot else { return }
        transition?.cancel()
        holdUntil = Date().addingTimeInterval(seconds)
        push(state, staleDate: staleDate(for: snapshot))

        transition = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.holdUntil = nil
            switch next {
            case .insulinOnBoard(let clearsAt):
                self.presentInsulinOnBoard(clearsAt: clearsAt)
            case .liveReading:
                if let snapshot = self.lastSnapshot {
                    self.push(self.glucoseState(from: snapshot), staleDate: self.staleDate(for: snapshot))
                }
            }
        }
    }

    private func push(_ state: GlucoseActivityAttributes.ContentState, staleDate: Date) {
        let store = self.store
        Task { await store.upsert(state: state, staleDate: staleDate) }
    }

    /// The live-reading presentation, and the base every momentary one builds on.
    private func baseState() -> GlucoseActivityAttributes.ContentState? {
        lastSnapshot.map(glucoseState(from:))
    }

    private func staleDate(for snapshot: GlucoseSnapshot) -> Date {
        snapshot.updatedAt.addingTimeInterval(30 * 60)
    }

    /// Projects a snapshot into the live-reading presentation: the headline state,
    /// its colour and glyph, the chart series and axis ticks, and the quick stats.
    private func glucoseState(from snapshot: GlucoseSnapshot) -> GlucoseActivityAttributes.ContentState {
        let outOfRange = snapshot.mgdL < snapshot.targetLowerMgdL
            || snapshot.mgdL > snapshot.targetUpperMgdL
        let isLow = snapshot.mgdL < snapshot.targetLowerMgdL
        let glucose = LiveActivityPresentation.state(
            mgdL: snapshot.mgdL,
            trendSymbol: snapshot.trendSymbol,
            targetLowerMgdL: snapshot.targetLowerMgdL,
            targetUpperMgdL: snapshot.targetUpperMgdL
        )
        // The last handful of readings feed the expanded sparkline. Capped small
        // so the activity's content payload stays well within budget.
        let recentPoints = Array(snapshot.points.suffix(16))
        let recent = recentPoints.map(\.mgdL)

        // The measured sensor cadence — the gap between the two most recent
        // readings, clamped to a sane 1–15 min — drives the "next reading" bar that
        // fills on its own. Measuring it from the data makes it correct for any
        // source (Dexcom ~5 min, Libre ~1 min) with no assumption; falls back to
        // 5 min when there aren't two points to measure from.
        let cadence: TimeInterval = {
            let pts = snapshot.points
            guard pts.count >= 2 else { return 5 * 60 }
            let gap = pts[pts.count - 1].date.timeIntervalSince(pts[pts.count - 2].date)
            return min(max(gap, 60), 15 * 60)
        }()

        let unit = GlucoseUnit(rawValue: snapshot.unitText) ?? .mgdL

        var state = GlucoseActivityAttributes.ContentState(
            mgdL: snapshot.mgdL,
            valueText: snapshot.valueText,
            unitText: snapshot.unitText,
            trendSymbol: snapshot.trendSymbol,
            trendLabel: snapshot.trendLabel,
            zoneLabel: snapshot.zoneLabel,
            zoneColorHex: snapshot.zoneColorHex,
            updatedAt: snapshot.updatedAt,
            isStale: snapshot.isStale,
            predictionText: snapshot.predictionText,
            iobText: snapshot.iobText,
            cobText: snapshot.cobText,
            targetLowerMgdL: snapshot.targetLowerMgdL,
            targetUpperMgdL: snapshot.targetUpperMgdL,
            isOutOfRange: outOfRange,
            recentMgdL: recent,
            forecastMgdL: snapshot.forecastMgdL,
            nextReadingAt: snapshot.updatedAt.addingTimeInterval(cadence)
        )

        state.kind = .glucose
        state.glucoseState = glucose
        state.stateColorHex = LiveActivityPresentation.colorHex(for: glucose)
        state.iconName = LiveActivityPresentation.iconName(for: .glucose, glucoseState: glucose)
        // The headline doubles as the live reading's title on both surfaces.
        state.eventTitle = LiveActivityPresentation.headline(for: glucose, isLow: isLow)
        state.eventCaption = LiveActivityPresentation.caption(for: glucose, isLow: isLow)

        // Quick statistics over the same window the chart shows.
        if let tir = LiveActivityPresentation.timeInRangePercent(
            recent, lower: snapshot.targetLowerMgdL, upper: snapshot.targetUpperMgdL) {
            state.tirText = "\(Int(tir.rounded()))%"
        }
        if let average = LiveActivityPresentation.average(recent) {
            state.averageText = GlucoseFormatting.string(mgdL: average, unit: unit)
        }
        if let deviation = LiveActivityPresentation.standardDeviation(recent) {
            // A spread, not a reading: convert the magnitude, don't re-baseline it.
            let converted = unit == .mmolL ? deviation / GlucoseUnit.conversionFactor : deviation
            let digits = unit == .mmolL ? 1 : 0
            state.deviationText = "±" + converted.formatted(.number.precision(.fractionLength(digits)))
        }

        // Axis ticks, pre-formatted so the widget never converts units or dates.
        if let lo = recent.min(), let hi = recent.max(), hi > lo {
            state.chartYLabels = [hi, (hi + lo) / 2, lo].map { GlucoseFormatting.string(mgdL: $0, unit: unit) }
        }
        state.chartXLabels = Self.xLabels(for: recentPoints)

        return state
    }

    /// Four x-axis ticks across the charted window, the last one reading "Now".
    private static func xLabels(for points: [GlucoseSnapshot.Point]) -> [String] {
        guard points.count >= 2 else { return [] }
        let formatter = Date.FormatStyle.dateTime.hour().minute()
        let indices = [0, points.count / 3, (points.count * 2) / 3]
        var labels = indices.map { points[min($0, points.count - 1)].date.formatted(formatter) }
        labels.append(String(localized: "Now"))
        return labels
    }

    /// "2:45" — the compact clock inside the pill.
    private static func clock(until date: Date, from now: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// "2h 45m" / "45m" — the spelled-out remaining time.
    private static func duration(until date: Date, from now: Date) -> String {
        let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
        // Reuses the catalog's existing duration phrasings, so no new plural forms.
        if minutes >= 60 { return String(localized: "\(minutes / 60)h \(minutes % 60)m") }
        return String(localized: "\(minutes) min")
    }
    #else
    func sync(with snapshot: GlucoseSnapshot) {}
    func end() {}
    func presentInsulinLogged(units: Double, clearsAt: Date, now: Date = Date()) {}
    func presentMealLogged(grams: Double, now: Date = Date()) {}
    func presentInsulinOnBoard(clearsAt: Date, now: Date = Date()) {}
    func presentMealCountdown(dueAt: Date, now: Date = Date()) {}
    func presentGlucoseAlert(isLow: Bool) {}
    func presentSensorReconnected(sourceName: String) {}
    func presentSensorBattery(percent: Int) {}
    #endif
}

#if canImport(ActivityKit) && os(iOS)
/// Owns the Live Activity handle in a nonisolated, `@unchecked Sendable` box.
///
/// ActivityKit's `request`/`update`/`end` are `nonisolated async`; if the handle
/// were stored on an actor (including `@MainActor`), Swift 6 region isolation
/// rejects passing that actor-isolated value into those nonisolated calls
/// ("sending 'activity' risks causing data races"). Keeping it here — off any
/// actor — means the handle lives in a disconnected region, so the calls type
/// check. Every entry point is funneled from the main actor via
/// `GlucoseLiveActivityManager`, and the payloads passed in are `Sendable`, so
/// the single stored handle is effectively serialized in practice.
private final class LiveActivityStore: @unchecked Sendable {
    private var activity: Activity<GlucoseActivityAttributes>?

    func upsert(state: GlucoseActivityAttributes.ContentState, staleDate: Date) async {
        let content = ActivityContent(state: state, staleDate: staleDate)

        // Re-adopt an activity started in a previous launch. The in-memory handle
        // is lost when the app is killed, but the Live Activity itself keeps
        // running — so without this we'd `request` a brand-new one on every
        // launch and they'd stack up on the Lock Screen (the "old one stays and a
        // new one appears" bug). Adopt the first existing activity and end any
        // extras a prior build may already have stacked.
        if activity == nil {
            let existing = Activity<GlucoseActivityAttributes>.activities
            activity = existing.first
            for extra in existing.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
        }

        if let activity {
            await activity.update(content)
        } else {
            activity = try? Activity.request(attributes: GlucoseActivityAttributes(), content: content)
        }
    }

    func finish() async {
        // End every running glucose activity, not just our handle, so any
        // duplicates left by an earlier build are cleared too.
        for a in Activity<GlucoseActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }
}
#endif
