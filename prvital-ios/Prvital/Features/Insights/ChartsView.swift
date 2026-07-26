import SwiftUI
import SwiftData
import Charts

/// The visual pane of Insights: an interval picker over `ChartsContent`, which is
/// re-created for each interval so only the selected window is ever loaded.
struct ChartsView: View {
    // Driven by the shared top-left menu in InsightsView.
    @Binding var interval: InsightsInterval

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Keyed on the interval so its windowed @Query re-initialises when
                // the range changes — a freshly imported 100k-row history is never
                // fully materialised, only the selected sub-range.
                ChartsContent(interval: interval)
                    .id(interval)
            }
            .padding()
            .animation(.smooth, value: interval)
        }
        .background(Theme.background)
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

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var medications: [MedicationDose]
    @Query private var ketones: [KetoneReading]
    @Query private var notes: [ObservationEntry]

    @State private var derived = ChartsDerived()
    /// Drives the distribution histogram's one-shot rise (bars grow from zero).
    @State private var histogramRisen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Apple Health's daily exercise minutes (appleExerciseTime — the Watch's green
    // ring) for the window, fetched off the render path and merged into the
    // Activity chart so it reflects real Watch activity, not only logged workouts.
    @State private var healthExercise: [DailyMetric] = []

    init(interval: InsightsInterval) {
        self.interval = interval
        let cutoff = interval.dateRange().lowerBound
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
        _medications = Query(filter: #Predicate<MedicationDose> { $0.timestamp >= cutoff },
                             sort: \.timestamp, order: .reverse)
        _ketones = Query(filter: #Predicate<KetoneReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _notes = Query(filter: #Predicate<ObservationEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
    }

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    private var eventKindsBinding: Binding<Set<ChartEventKind>> {
        Binding(get: { env.preferences.chartEventKinds },
                set: { env.preferences.chartEventKinds = $0 })
    }

    /// Cheap, Equatable fingerprint of the inputs. Changes only when data is
    /// added/removed (or the interval switches), so ordinary re-renders reuse the
    /// cached results instead of recomputing.
    private var signature: ChartsSignature {
        ChartsSignature(
            interval: interval,
            glucose: glucose.count, insulin: insulin.count, carbs: carbs.count,
            activity: activity.count, medications: medications.count,
            ketones: ketones.count, notes: notes.count,
            newest: glucose.first?.timestamp,
            healthExerciseDays: healthExercise.count,
            healthExerciseTotal: Int(healthExercise.reduce(0.0) { $0 + $1.value }.rounded())
        )
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 20) {
            if derived.ready {
                glucoseSection.appearTransition(delay: 0)
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
        .task(id: signature) {
            await derived.rebuild(
                glucose: glucose, insulin: insulin, carbs: carbs, activity: activity,
                medications: medications, ketones: ketones, notes: notes,
                healthExercise: healthExercise, range: interval.dateRange())
        }
        // Pull the window's Apple Health exercise minutes; when they land the
        // signature changes and the rebuild re-runs to merge them in.
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

/// A cheap fingerprint of the chart inputs. `.task(id:)` reruns the rebuild only
/// when this changes, so scrolls/animations/sheet toggles never recompute.
struct ChartsSignature: Equatable {
    let interval: InsightsInterval
    let glucose: Int
    let insulin: Int
    let carbs: Int
    let activity: Int
    let medications: Int
    let ketones: Int
    let notes: Int
    let newest: Date?
    let healthExerciseDays: Int
    let healthExerciseTotal: Int
}

/// Holds the prepared, already-aggregated chart data. Rebuilt once per data
/// change on the main actor (SwiftData objects are main-actor bound), with a
/// yield after the initial filter so the pane can paint before the heavier
/// aggregation runs.
@MainActor
@Observable
final class ChartsDerived {
    var ready = false
    /// Downsampled glucose readings for the trend line (see `downsample`).
    var chartReadings: [GlucoseReading] = []
    var distribution: [DistributionBin] = []
    var chartEvents: [ChartEvent] = []
    var insulinBars: [ChartsInsulinBar] = []
    var carbBars: [ChartsDailyBar] = []
    var activityBars: [ChartsDailyBar] = []
    var heatmap = GlucoseHeatmap(blocksPerDay: 8, averages: [])

    /// Cap on the number of points fed to the glucose trend chart. A month is
    /// ~8.6k CGM readings and a year ~100k; Swift Charts renders a mark per
    /// point, so uncapped it stalled for seconds. ~500 points draws a smooth
    /// line instantly.
    private static let maxTrendPoints = 500

    func rebuild(
        glucose: [GlucoseReading], insulin: [InsulinDose], carbs: [CarbEntry],
        activity: [ActivityEntry], medications: [MedicationDose], ketones: [KetoneReading],
        notes: [ObservationEntry], healthExercise: [DailyMetric], range: ClosedRange<Date>
    ) async {
        let active = glucose.filter { $0.isActive && range.contains($0.timestamp) }
        let fInsulin = insulin.filter { range.contains($0.timestamp) }
        let fCarbs = carbs.filter { range.contains($0.timestamp) }
        let fActivity = activity.filter { range.contains($0.startTimestamp) }
        let fMeds = medications.filter { range.contains($0.timestamp) }
        let fKetones = ketones.filter { range.contains($0.timestamp) }
        let fNotes = notes.filter { range.contains($0.timestamp) }

        // Let the first frame paint (loading placeholder) before the heavier work.
        await Task.yield()

        let distribution = GlucoseDistribution.bins(active)
        let events = ChartEvent.build(insulin: fInsulin, meals: fCarbs,
                                      medications: fMeds, activity: fActivity,
                                      ketones: fKetones, notes: fNotes)
        let insulinBars = Self.insulinBars(fInsulin)
        let carbBars = Self.dailyTotals(fCarbs.map { ($0.timestamp, $0.grams) })
        let activityBars = Self.activityBars(
            logged: fActivity.map { ($0.startTimestamp, Double($0.durationMinutes)) },
            health: healthExercise, range: range)
        let trend = Self.downsample(active, maxPoints: Self.maxTrendPoints)
        let heatmap = GlucoseHeatmap.build(active)

        self.heatmap = heatmap
        self.distribution = distribution
        self.chartEvents = events
        self.insulinBars = insulinBars
        self.carbBars = carbBars
        self.activityBars = activityBars
        self.chartReadings = trend
        self.ready = true
    }

    /// Evenly thins a time-ordered reading series down to at most `maxPoints`,
    /// preserving chronological order. Returns the real `GlucoseReading` objects
    /// (a subset), so no synthetic samples are created.
    static func downsample(_ readings: [GlucoseReading], maxPoints: Int) -> [GlucoseReading] {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > maxPoints, maxPoints > 0 else { return sorted }
        let stride = Double(sorted.count) / Double(maxPoints)
        var result: [GlucoseReading] = []
        result.reserveCapacity(maxPoints)
        var cursor = 0.0
        while Int(cursor) < sorted.count {
            result.append(sorted[Int(cursor)])
            cursor += stride
        }
        // Always keep the final reading so the line reaches "now".
        if let last = sorted.last, result.last?.timestamp != last.timestamp {
            result.append(last)
        }
        return result
    }

    /// Daily insulin totals split into basal and bolus stacks.
    static func insulinBars(_ doses: [InsulinDose]) -> [ChartsInsulinBar] {
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
