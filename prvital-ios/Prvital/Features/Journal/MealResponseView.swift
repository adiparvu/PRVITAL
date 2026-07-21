import SwiftUI
import SwiftData
import Charts

/// The postprandial response to one meal: the glucose curve from the meal across
/// a configurable window, with the meal and window-end markers, the peak, and the
/// metrics that matter — how far it rose, when it peaked, how long it stayed up,
/// how much of the window was in range, and the bolus that went with it. Presented
/// as a sheet when a meal is tapped in the journal; "Edit" opens the meal editor.
struct MealResponseView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let meal: CarbEntry

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var allMeals: [CarbEntry]

    @State private var showEditor = false

    init(meal: CarbEntry) {
        self.meal = meal
        // Scope the reading/insulin queries to the widest possible window (4h)
        // plus a small margin, so a CGM user's full history never loads here.
        let start = meal.timestamp.addingTimeInterval(-30 * 60)
        let end = meal.timestamp.addingTimeInterval(4 * 3600 + 30 * 60)
        _glucose = Query(
            filter: #Predicate<GlucoseReading> { $0.timestamp >= start && $0.timestamp <= end },
            sort: \.timestamp, order: .forward)
        _insulin = Query(
            filter: #Predicate<InsulinDose> { $0.timestamp >= start && $0.timestamp <= end },
            sort: \.timestamp, order: .forward)
    }

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var windowHours: Int { env.preferences.postprandialWindowHours }

    private var response: MealResponse {
        MealResponseAnalyzer.analyze(
            meal: meal, readings: glucose, insulin: insulin,
            thresholds: thresholds, windowHours: windowHours)
    }

    private var windowBinding: Binding<Int> {
        Binding(
            get: { env.preferences.postprandialWindowHours },
            set: { Haptics.play(.selection); env.preferences.postprandialWindowHours = $0 }
        )
    }

    var body: some View {
        let response = self.response

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(response)
                    windowPicker
                    if response.hasData {
                        MealResponseChart(response: response, thresholds: thresholds, unit: unit)
                            .frame(height: 210)
                            .glassCard(cornerRadius: 24, padding: 16)
                        metrics(response)
                        comparison
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Meal response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { Haptics.play(.selection); showEditor = true }
                }
            }
            .sheet(isPresented: $showEditor) { CarbEntrySheet(existing: meal) }
        }
    }

    // MARK: - Header

    private func header(_ response: MealResponse) -> some View {
        HStack(spacing: 14) {
            Image(systemName: meal.mealType.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.zoneHigh)
                .frame(width: 46, height: 46)
                .background(Theme.zoneHigh.opacity(0.14), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(meal.mealType.label) · \(gramsText)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let food = meal.foodDescription, !food.isEmpty {
                    Text(food).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Text(baselineLine(response))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Label(response.rating.title, systemImage: response.rating.symbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(ratingTint(response.rating))
                .accessibilityLabel(response.rating.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, padding: 16)
    }

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compare window").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Picker("Compare window", selection: windowBinding) {
                ForEach(1...4, id: \.self) { h in
                    Text(h == 1 ? String(localized: "1h") : String(localized: "\(h)h")).tag(h)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Metrics

    private func metrics(_ r: MealResponse) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            metric("Peak", peakText(r), "arrow.up.to.line", r.peakMgdL.map { thresholds.zone(forMgdL: $0).color } ?? Theme.textSecondary)
            metric("Rise from baseline", deltaText(r), "arrow.up.forward", Theme.zoneHigh)
            metric("Back near baseline", returnText(r), "arrow.uturn.down", Theme.zoneInRange)
            metric("In range after", inRangeText(r), "target", Theme.zoneInRange)
            metric("Excursion", aucText(r), "chart.line.uptrend.xyaxis", Theme.accent)
            metric("Bolus", bolusText(r), "syringe.fill", Theme.accent)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                Text(title).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Comparison

    @ViewBuilder
    private var comparison: some View {
        if let previous = MealResponseAnalyzer.previousComparable(to: meal, among: allMeals) {
            let prev = MealResponseAnalyzer.analyze(
                meal: previous, readings: glucose, insulin: insulin,
                thresholds: thresholds, windowHours: windowHours)
            // The scoped query only covers *this* meal's window, so a previous
            // meal usually has no trace here — show the comparison only when it
            // genuinely does, otherwise the line would be misleading.
            if let thisDelta = response.deltaMgdL, let prevDelta = prev.deltaMgdL, prev.hasData {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(Theme.accent)
                    Text(comparisonText(thisDelta: thisDelta, prevDelta: prevDelta, previous: previous))
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 16, padding: 0)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.dots.scatter").font(.largeTitle).foregroundStyle(Theme.textTertiary)
            Text("Not enough readings around this meal to show a response yet.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Text

    private var gramsText: String { String(localized: "\(meal.grams.formatted()) g") }

    private func baselineLine(_ r: MealResponse) -> String {
        let time = meal.timestamp.formatted(date: .omitted, time: .shortened)
        if let base = r.baselineMgdL {
            return String(localized: "\(GlucoseFormatting.labeled(mgdL: base, unit: unit)) at \(time)")
        }
        return time
    }

    private func peakText(_ r: MealResponse) -> String {
        guard let peak = r.peakMgdL, let mins = r.minutesToPeak else { return "—" }
        return String(localized: "\(GlucoseFormatting.string(mgdL: peak, unit: unit)) · \(mins) min")
    }
    private func deltaText(_ r: MealResponse) -> String {
        guard let d = r.deltaMgdL else { return "—" }
        let sign = d >= 0 ? "+" : ""
        return "\(sign)\(GlucoseFormatting.labeled(mgdL: d, unit: unit))"
    }
    private func returnText(_ r: MealResponse) -> String {
        guard let m = r.returnMinutes else { return String(localized: "Not yet") }
        return String(localized: "\(m) min")
    }
    private func inRangeText(_ r: MealResponse) -> String {
        guard let p = r.inRangePercent else { return "—" }
        return "\(Int((p * 100).rounded()))%"
    }
    private func aucText(_ r: MealResponse) -> String {
        guard r.excursionAUC > 0 else { return "—" }
        return String(localized: "\(Int(r.excursionAUC.rounded())) mg·h")
    }
    private func bolusText(_ r: MealResponse) -> String {
        guard let u = r.bolusUnits else { return String(localized: "None") }
        return String(localized: "\(u.formatted()) U")
    }

    private func comparisonText(thisDelta: Double, prevDelta: Double, previous: CarbEntry) -> String {
        let diff = thisDelta - prevDelta
        let when = previous.timestamp.formatted(date: .abbreviated, time: .omitted)
        if abs(diff) < 8 {
            return String(localized: "About the same rise as your last \(meal.mealType.label.lowercased()) (\(when)).")
        }
        if diff < 0 {
            return String(localized: "Rose \(GlucoseFormatting.labeled(mgdL: -diff, unit: unit)) less than your last \(meal.mealType.label.lowercased()) (\(when)).")
        }
        return String(localized: "Rose \(GlucoseFormatting.labeled(mgdL: diff, unit: unit)) more than your last \(meal.mealType.label.lowercased()) (\(when)).")
    }

    private func ratingTint(_ rating: MealResponseRating) -> Color {
        switch rating {
        case .steady: Theme.zoneInRange
        case .gentle: Theme.zoneInRange
        case .notable: Theme.zoneHigh
        case .high: Theme.zoneWarning
        }
    }
}

// MARK: - Chart

/// The response curve with the meal + window-end markers, target lines and the
/// peak highlighted. Kept separate so the view above stays about the metrics.
private struct MealResponseChart: View {
    let response: MealResponse
    let thresholds: GlucoseThresholds
    let unit: GlucoseUnit

    private var yDomain: ClosedRange<Double> {
        let values = response.points.map(\.mgdL)
        let lo = min(values.min() ?? thresholds.targetLower, thresholds.targetLower) - 15
        let hi = max(values.max() ?? thresholds.targetUpper, thresholds.targetUpper) + 20
        return max(0, lo)...hi
    }

    private var peakPoint: MealResponsePoint? {
        guard let peak = response.peakMgdL else { return nil }
        return response.points.first { $0.mgdL == peak && $0.date > response.mealTime }
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("High", thresholds.targetUpper))
                .foregroundStyle(Theme.zoneHigh.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Low", thresholds.targetLower))
                .foregroundStyle(Theme.zoneWarning.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(response.points) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Glucose", point.mgdL))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
            }
            ForEach(response.points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Glucose", point.mgdL))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(markerLines) { marker in
                RuleMark(x: .value("Marker", marker.date))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text(marker.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .shadow(color: Theme.background, radius: 2)
                    }
            }

            if let peak = peakPoint {
                PointMark(x: .value("Time", peak.date), y: .value("Glucose", peak.mgdL))
                    .foregroundStyle(thresholds.zone(forMgdL: peak.mgdL).color)
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 4) {
                        Text(GlucoseFormatting.string(mgdL: peak.mgdL, unit: unit))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(thresholds.zone(forMgdL: peak.mgdL).color)
                            .shadow(color: Theme.background, radius: 2)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(GlucoseFormatting.string(mgdL: v, unit: unit))
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.4))
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartPlotStyle { $0.clipped() }
        .padding(.top, 10)
    }

    /// Only the meal (0h) and the window-end markers get drawn — showing every
    /// hour would clutter the compact chart.
    private var markerLines: [MealResponseMarker] {
        let ends = [response.markers.first, response.markers.last].compactMap { $0 }
        // De-dupe when the window is 0 (shouldn't happen) or identical.
        var seen = Set<Int>()
        return ends.filter { seen.insert($0.hoursAfter).inserted }
    }
}
