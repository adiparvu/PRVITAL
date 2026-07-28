import SwiftUI
import SwiftData
import Charts

/// The visual pane of Insights: an interval picker over `ChartsContent`, which is
/// re-created for each interval so only the selected window is ever loaded.
struct ChartsView: View {
    // Driven by the shared top-left menu in InsightsView.
    @Binding var interval: InsightsInterval
    /// The Insights feed, rendered as the first scrolling element so it moves
    /// with the page as one whole. No opaque background here either — the
    /// tab's wallpaper shows through everything (device feedback).
    var pinnedHeader: AnyView? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let pinnedHeader { pinnedHeader }
                // Keyed on the interval so its windowed @Query re-initialises when
                // the range changes — a freshly imported 100k-row history is never
                // fully materialised, only the selected sub-range.
                ChartsContent(interval: interval)
                    .id(interval)
            }
            .padding()
            .animation(.smooth, value: interval)
        }
    }
}

/// The charts for one interval. Every `@Query` is windowed to that interval's
/// `dateRange()` in `init`, per the data guidelines, so the always-visible
/// Insights tab never loads the whole CGM history on the main thread.
///
/// All the filtering + aggregation is done ONCE per data change inside a
/// `.task(id:)`, into a cached `ChartsDerived`, instead of in the view `body`.
/// Previously every re-render (a scroll, a background HealthKit import, an
/// animation) re-ran a dozen `filter`/aggregate passes over thousands of CGM
/// readings on the main thread, and the raw readings were handed straight to
/// Swift Charts — which is why the tab loaded slowly and stuttered. Now the
/// heavy work runs off the first-paint path and the trend line is downsampled.
struct ChartsContent: View {
    @Environment(AppEnvironment.self) private var env

    let interval: InsightsInterval

    @State private var derived = ChartsDerived()
    /// Drives the distribution histogram's one-shot rise (bars grow from zero).
    @State private var histogramRisen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Apple Health's daily exercise minutes (appleExerciseTime — the Watch's green
    // ring) for the window, fetched off the render path and merged into the
    // Activity chart so it reflects real Watch activity, not only logged workouts.
    @State private var healthExercise: [DailyMetric] = []

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    private var eventKindsBinding: Binding<Set<ChartEventKind>> {
        Binding(get: { env.preferences.chartEventKinds },
                set: { env.preferences.chartEventKinds = $0 })
    }

    /// Rebuild trigger: the interval, the store's data version (bumped on every
    /// write/sync) and the Health exercise merge — no live `@Query` involved.
    private struct BuildKey: Equatable {
        let interval: InsightsInterval
        let dataVersion: Int
        let exerciseDays: Int
        let exerciseTotal: Int
    }

    private var buildKey: BuildKey {
        BuildKey(interval: interval,
                 dataVersion: env.dataVersion,
                 exerciseDays: healthExercise.count,
                 exerciseTotal: Int(healthExercise.reduce(0.0) { $0 + $1.value }.rounded()))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 20) {
            if derived.ready {
                glucoseSection.appearTransition(delay: 0)
                if derived.overlayDays.count >= 2 {
                    overlaySection.appearTransition(delay: 0.03)
                }
                distributionSection.appearTransition(delay: 0.06)
                if derived.heatmap.hasData {
                    GlucoseHeatmapCard(heatmap: derived.heatmap, unit: unit, thresholds: thresholds)
                        .appearTransition(delay: 0.09)
                }
                insulinSection.appearTransition(delay: 0.12)
                carbsSection.appearTransition(delay: 0.18)
                activitySection.appearTransition(delay: 0.24)
            } else {
                loadingPlaceholder
            }
        }
        .task(id: buildKey) {
            // Fetch + aggregate on a background ModelActor — a Year window is
            // ~100k CGM rows, and holding it in a live @Query re-materialised
            // all of them on the MAIN thread on every store change while the
            // Insights tab was alive. Only applying the finished payload (and
            // building ≤500 detached trend points) touches the main actor.
            let builder = ChartsBuilder(modelContainer: env.modelContainer)
            let payload = await builder.build(
                range: interval.dateRange(), healthExercise: healthExercise)
            derived.apply(payload)
        }
        // Pull the window's Apple Health exercise minutes; when they land the
        // build key changes and the builder re-runs to merge them in.
        .task(id: interval) {
            healthExercise = await env.healthKit.dailyMetric(.exercise, days: interval.dayCount)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing your charts…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: Sections

    private var distributionSection: some View {
        SectionCard("Glucose distribution", systemImage: "chart.bar.xaxis") {
            if derived.distribution.isEmpty {
                emptyChart("No glucose readings in this period.")
            } else {
                Chart(derived.distribution) { bin in
                    // Bars rise from zero on first appearance — see histogramRisen.
                    BarMark(
                        x: .value("Glucose", bin.midpoint),
                        y: .value("Readings", histogramRisen ? bin.count : 0),
                        width: .fixed(9)
                    )
                    .foregroundStyle(barColor(bin).gradient)
                    .cornerRadius(2)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8),
                           value: histogramRisen)
                .task { histogramRisen = true }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 40)) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let mgdL = value.as(Double.self) {
                                Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private func barColor(_ bin: DistributionBin) -> Color {
        switch thresholds.zone(forMgdL: bin.midpoint) {
        case .veryLow, .low: return Theme.zoneWarning
        case .inRange: return Theme.zoneInRange
        case .high, .veryHigh: return Theme.zoneHigh
        }
    }

    private var glucoseSection: some View {
        SectionCard("Glucose trend", systemImage: "waveform.path.ecg") {
            if derived.chartReadings.isEmpty {
                emptyChart("No glucose readings in this period.")
            } else {
                GlucoseTrendChart(readings: derived.chartReadings, thresholds: thresholds, unit: unit,
                                  events: derived.chartEvents,
                                  visibleEventKinds: env.preferences.chartEventKinds,
                                  eventKindsBinding: eventKindsBinding,
                                  eventBand: true)
            }
        }
    }

    /// The Clarity-style "modal day": every recent day drawn over the same
    /// 0–24 h axis, the most recent in accent on top — the fastest way to see
    /// "I always rise at 7 AM". Faded days carry no identity on purpose; the
    /// pattern, not any single line, is the reading.
    private var overlaySection: some View {
        SectionCard("Days overlaid", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 10) {
                Chart {
                    RectangleMark(
                        xStart: .value("Hour", 0.0), xEnd: .value("Hour", 24.0),
                        yStart: .value("Glucose", unit.fromMgdL(thresholds.targetLower)),
                        yEnd: .value("Glucose", unit.fromMgdL(thresholds.targetUpper))
                    )
                    .foregroundStyle(Theme.zoneInRange.opacity(0.10))

                    ForEach(derived.overlayDays) { day in
                        let isLatest = day.id == derived.overlayDays.last?.id
                        ForEach(Array(day.points.enumerated()), id: \.offset) { _, point in
                            LineMark(
                                x: .value("Hour", point.hour),
                                y: .value("Glucose", unit.fromMgdL(point.mgdL)),
                                series: .value("Day", day.id.timeIntervalSince1970)
                            )
                            .foregroundStyle(isLatest ? Theme.accent : Theme.textTertiary.opacity(0.32))
                            .lineStyle(StrokeStyle(lineWidth: isLatest ? 2.5 : 1.2,
                                                   lineCap: .round, lineJoin: .round))
                        }
                        .interpolationMethod(.monotone)
                    }
                }
                .chartXScale(domain: 0...24)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.6))
                        AxisValueLabel {
                            if let hour = value.as(Double.self) {
                                Text(verbatim: String(format: "%02d", Int(hour) % 24))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.4))
                        AxisValueLabel {
                            if let level = value.as(Double.self) {
                                Text(verbatim: level.formatted(
                                    .number.precision(.fractionLength(unit.fractionDigits))))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 220)

                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Capsule().fill(Theme.accent).frame(width: 16, height: 3)
                        if let latest = derived.overlayDays.last {
                            Text(latest.id, format: .dateTime.weekday(.wide).day().month())
                        }
                    }
                    HStack(spacing: 5) {
                        Capsule().fill(Theme.textTertiary.opacity(0.5)).frame(width: 16, height: 3)
                        Text("Previous \(derived.overlayDays.count - 1) days")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var insulinSection: some View {
        SectionCard("Insulin", systemImage: "syringe.fill") {
            if derived.insulinBars.isEmpty {
                emptyChart("No insulin doses in this period.")
            } else {
                Chart(derived.insulinBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Units", bar.units)
                    )
                    .foregroundStyle(by: .value("Type", bar.category.label))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale([
                    ChartsInsulinBar.Category.bolus.label: Theme.accent,
                    ChartsInsulinBar.Category.basal.label: Theme.zoneWarning,
                ])
                .chartLegend(position: .bottom, spacing: 8)
                .chartXAxis { dateAxis }
                .chartYAxis { unitsAxis(suffix: "U") }
                .frame(height: 200)
                .accessibilityLabel("Daily insulin units, basal and bolus")
            }
        }
    }

    private var carbsSection: some View {
        SectionCard("Carbohydrates", systemImage: "fork.knife") {
            if derived.carbBars.isEmpty {
                emptyChart("No meals logged in this period.")
            } else {
                Chart(derived.carbBars) { bar in
                    BarMark(
                        x: .value("Day", bar.day, unit: .day),
                        y: .value("Grams", bar.total)
                    )
                    .foregroundStyle(Theme.zoneHigh.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis { dateAxis }
                .chartYAxis { unitsAxis(suffix: "g") }
                .frame(height: 180)
                .accessibilityLabel("Daily carbohydrate grams")
            }
        }
    }

    private var activitySection: some View {
        SectionCard("Activity", systemImage: "figure.walk") {
            VStack(spacing: 14) {
                if derived.activityBars.isEmpty {
                    emptyChart("No activity logged in this period.")
                } else {
                    Chart(derived.activityBars) { bar in
                        BarMark(
                            x: .value("Day", bar.day, unit: .day),
                            y: .value("Minutes", bar.total)
                        )
                        .foregroundStyle(Theme.zoneInRange.gradient)
                        .cornerRadius(4)
                    }
                    .chartXAxis { dateAxis }
                    .chartYAxis { unitsAxis(suffix: "min") }
                    .frame(height: 180)
                    .accessibilityLabel("Daily active minutes")
                }

                Divider().overlay(Theme.hairline)
                NavigationLink {
                    MovementGlucoseView(date: Date())
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                        Text("Movement & glucose")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Shared axis + empty

    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
            AxisTick().foregroundStyle(Theme.hairline)
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
        }
    }

    private func unitsAxis(suffix: String) -> some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine().foregroundStyle(Theme.hairline)
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text("\(number.formatted(.number.precision(.fractionLength(0)))) \(suffix)")
                }
            }
        }
    }

    private func emptyChart(_ message: LocalizedStringKey) -> some View {
        EmptyStateView(
            systemImage: "chart.bar",
            title: "No data",
            message: message
        )
    }
}

// MARK: - Derived (computed once per data change, off the render path)

/// Holds the prepared, already-aggregated chart data on the main actor. The
/// heavy lifting happens in `ChartsBuilder` on a background ModelActor; this
/// only stores the finished payload and materialises the ≤500 detached trend
/// readings the chart view consumes.
@MainActor
@Observable
final class ChartsDerived {
    var ready = false
    /// Detached (never-inserted) readings for the trend line — built from the
    /// payload's value points, ≤500 of them.
    var chartReadings: [GlucoseReading] = []
    var distribution: [DistributionBin] = []
    var chartEvents: [ChartEvent] = []
    var insulinBars: [ChartsInsulinBar] = []
    var carbBars: [ChartsDailyBar] = []
    var activityBars: [ChartsDailyBar] = []
    var overlayDays: [ChartsPayload.OverlayDay] = []
    var heatmap = GlucoseHeatmap(blocksPerDay: 8, averages: [])

    func apply(_ payload: ChartsPayload) {
        heatmap = payload.heatmap
        overlayDays = payload.overlayDays
        distribution = payload.distribution
        chartEvents = payload.events
        insulinBars = payload.insulinBars
        carbBars = payload.carbBars
        activityBars = payload.activityBars
        chartReadings = payload.trend.map {
            GlucoseReading(
                valueMgdL: $0.mgdL, timestamp: $0.date,
                source: DataSource(rawValue: $0.sourceRaw) ?? .manual,
                measurementType: GlucoseMeasurementType(rawValue: $0.typeRaw) ?? .cgm)
        }
        ready = true
    }
}

/// The finished, fully value-typed chart data a `ChartsBuilder` run produces —
/// safe to hop actors with.
struct ChartsPayload: Sendable {
    struct TrendPoint: Sendable {
        let date: Date
        let mgdL: Double
        let sourceRaw: String
        let typeRaw: String
    }

    /// One day's glucose curve folded onto a 0–24 h axis, for the
    /// Clarity-style "daily overlay" chart.
    struct OverlayDay: Sendable, Identifiable {
        /// Start of the calendar day — doubles as the identity and legend date.
        let id: Date
        /// (fractional hour of day, mg/dL), time-ordered, ≤48 points.
        let points: [OverlayPoint]
    }

    struct OverlayPoint: Sendable {
        let hour: Double
        let mgdL: Double
    }

    var trend: [TrendPoint] = []
    /// Most recent days of the window (≤14, newest last), each folded onto a
    /// 24 h axis. Empty when the window spans fewer than 3 calendar days.
    var overlayDays: [OverlayDay] = []
    var distribution: [DistributionBin] = []
    var events: [ChartEvent] = []
    var insulinBars: [ChartsInsulinBar] = []
    var carbBars: [ChartsDailyBar] = []
    var activityBars: [ChartsDailyBar] = []
    var heatmap = GlucoseHeatmap(blocksPerDay: 8, averages: [])
}

/// Fetches and aggregates the Charts pane's window on a background ModelActor.
/// A Year window is ~100k CGM rows; doing this behind a live `@Query` kept all
/// of them materialising on the MAIN thread on every store change for as long
/// as the Insights tab stayed alive.
@ModelActor
actor ChartsBuilder {
    /// Cap on the number of points fed to the glucose trend chart. Swift Charts
    /// renders a mark per point; ~500 draws a smooth line instantly.
    private static let maxTrendPoints = 500

    func build(range: ClosedRange<Date>, healthExercise: [DailyMetric]) -> ChartsPayload {
        let lower = range.lowerBound
        let upper = range.upperBound

        let active = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let fInsulin = (try? modelContext.fetch(FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let fCarbs = (try? modelContext.fetch(FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let fActivity = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.startTimestamp >= lower && $0.startTimestamp <= upper }))) ?? []
        let fMeds = (try? modelContext.fetch(FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let fKetones = (try? modelContext.fetch(FetchDescriptor<KetoneReading>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []
        let fNotes = (try? modelContext.fetch(FetchDescriptor<ObservationEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }))) ?? []

        var payload = ChartsPayload()
        payload.distribution = GlucoseDistribution.bins(active)
        payload.events = ChartEvent.build(insulin: fInsulin, meals: fCarbs,
                                          medications: fMeds, activity: fActivity,
                                          ketones: fKetones, notes: fNotes)
        payload.insulinBars = Self.insulinBars(fInsulin)
        payload.carbBars = Self.dailyTotals(fCarbs.map { ($0.timestamp, $0.grams) })
        payload.activityBars = Self.activityBars(
            logged: fActivity.map { ($0.startTimestamp, Double($0.durationMinutes)) },
            health: healthExercise, range: range)
        payload.trend = Self.downsample(active, maxPoints: Self.maxTrendPoints).map {
            ChartsPayload.TrendPoint(date: $0.timestamp, mgdL: $0.valueMgdL,
                                     sourceRaw: $0.sourceRaw, typeRaw: $0.measurementTypeRaw)
        }
        payload.overlayDays = Self.overlayDays(active, range: range)
        payload.heatmap = GlucoseHeatmap.build(active)
        return payload
    }

    /// Folds the window's readings into per-day 24 h curves for the overlay
    /// chart: the most recent ≤14 calendar days with data, newest last, each
    /// day thinned to ≤48 points so a full overlay stays under ~700 marks.
    private static func overlayDays(
        _ active: [GlucoseReading], range: ClosedRange<Date>
    ) -> [ChartsPayload.OverlayDay] {
        let calendar = Calendar.current
        let spanDays = calendar.dateComponents(
            [.day], from: range.lowerBound, to: range.upperBound).day ?? 0
        guard spanDays >= 3 else { return [] }

        var byDay: [Date: [GlucoseReading]] = [:]
        for reading in active {
            byDay[calendar.startOfDay(for: reading.timestamp), default: []].append(reading)
        }
        let recentDays = byDay.keys.sorted().suffix(14)
        return recentDays.compactMap { day in
            guard let readings = byDay[day], readings.count >= 3 else { return nil }
            let thinned = downsample(readings.sorted { $0.timestamp < $1.timestamp }, maxPoints: 48)
            let points = thinned.map { reading in
                ChartsPayload.OverlayPoint(
                    hour: reading.timestamp.timeIntervalSince(day) / 3600,
                    mgdL: reading.valueMgdL)
            }
            return ChartsPayload.OverlayDay(id: day, points: points)
        }
    }

    /// Evenly thins a time-ordered reading series down to at most `maxPoints`,
    /// preserving chronological order.
    private static func downsample(_ readings: [GlucoseReading], maxPoints: Int) -> [GlucoseReading] {
        guard readings.count > maxPoints, maxPoints > 0 else { return readings }
        let stride = Double(readings.count) / Double(maxPoints)
        var result: [GlucoseReading] = []
        result.reserveCapacity(maxPoints)
        var cursor = 0.0
        while Int(cursor) < readings.count {
            result.append(readings[Int(cursor)])
            cursor += stride
        }
        // Always keep the final reading so the line reaches "now".
        if let last = readings.last, result.last?.timestamp != last.timestamp {
            result.append(last)
        }
        return result
    }

    /// Daily insulin totals split into basal and bolus stacks.
    private static func insulinBars(_ doses: [InsulinDose]) -> [ChartsInsulinBar] {
        let calendar = Calendar.current
        var basal: [Date: Double] = [:]
        var bolus: [Date: Double] = [:]
        for dose in doses {
            let day = calendar.startOfDay(for: dose.timestamp)
            if dose.insulinType.isBasal { basal[day, default: 0] += dose.units }
            else { bolus[day, default: 0] += dose.units }
        }
        var bars: [ChartsInsulinBar] = []
        for (day, units) in bolus where units > 0 {
            bars.append(ChartsInsulinBar(day: day, units: units, category: .bolus))
        }
        for (day, units) in basal where units > 0 {
            bars.append(ChartsInsulinBar(day: day, units: units, category: .basal))
        }
        return bars.sorted { $0.day < $1.day }
    }

    static func dailyTotals(_ items: [(Date, Double)]) -> [ChartsDailyBar] {
        let calendar = Calendar.current
        var totals: [Date: Double] = [:]
        for (date, value) in items {
            totals[calendar.startOfDay(for: date), default: 0] += value
        }
        return totals
            .map { ChartsDailyBar(day: $0.key, total: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Daily active-minute bars combining logged workouts with Apple Health's
    /// exercise total. Apple Health's `appleExerciseTime` already counts logged
    /// workout time, so per day we take the LARGER of the two (never the sum) to
    /// avoid double counting — the same rule the Move ring uses.
    static func activityBars(logged: [(Date, Double)], health: [DailyMetric],
                             range: ClosedRange<Date>) -> [ChartsDailyBar] {
        let calendar = Calendar.current
        var loggedByDay: [Date: Double] = [:]
        for (date, value) in logged {
            loggedByDay[calendar.startOfDay(for: date), default: 0] += value
        }
        var healthByDay: [Date: Double] = [:]
        let lowerDay = calendar.startOfDay(for: range.lowerBound)
        for metric in health where metric.day >= lowerDay {
            healthByDay[calendar.startOfDay(for: metric.day)] = metric.value
        }
        let days = Set(loggedByDay.keys).union(healthByDay.keys)
        return days
            .map { ChartsDailyBar(day: $0, total: max(loggedByDay[$0] ?? 0, healthByDay[$0] ?? 0)) }
            .filter { $0.total > 0 }
            .sorted { $0.day < $1.day }
    }
}

// MARK: - Chart aggregation models

/// A single stacked slice of daily insulin (basal or bolus).
struct ChartsInsulinBar: Identifiable {
    enum Category {
        case basal, bolus
        var label: String { self == .basal ? String(localized: "Basal") : String(localized: "Bolus") }
    }

    let id = UUID()
    let day: Date
    let units: Double
    let category: Category
}

/// A single-value daily bar (carbs grams or activity minutes).
struct ChartsDailyBar: Identifiable {
    let id = UUID()
    let day: Date
    let total: Double
}

#Preview {
    let env = AppEnvironment.preview()
    return ChartsView(interval: .constant(.week))
        .environment(env)
        .modelContainer(env.modelContainer)
}
