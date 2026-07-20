import SwiftUI
import SwiftData

/// The Dashboard — the app's first screen. Shows the current glucose value as a
/// hero gauge, the last three hours as a trend chart, and the most recent
/// insulin / meal / activity at a glance. All reads are reactive `@Query`s that
/// are filtered and summarised in the view; the single write path is presenting
/// the shared entry editors.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var readings: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]

    @State private var showQuickEntry = false
    @State private var showGlucoseEntry = false

    var body: some View {
        let thresholds = env.preferences.thresholds
        let unit = env.preferences.glucoseUnit
        let summary = DashboardSummary.make(
            readings: readings,
            insulin: insulin,
            carbs: carbs,
            activity: activity,
            thresholds: thresholds
        )

        let bolus = env.preferences.bolusParameters
        let todayStats = DailyGlucose.today(readings, thresholds: thresholds)

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero(summary: summary, thresholds: thresholds, unit: unit)
                        .appearTransition(delay: 0)
                    trendSection(summary: summary, thresholds: thresholds, unit: unit)
                        .appearTransition(delay: 0.06)
                    if todayStats.hasGlucose {
                        todayCard(todayStats)
                            .appearTransition(delay: 0.12)
                    }
                    if bolus.isEnabled && bolus.isValid {
                        let now = Date()
                        onBoardCard(
                            iob: InsulinMath.activeInsulin(doses: insulin, at: now, parameters: bolus),
                            cob: CarbMath.carbsOnBoard(entries: carbs, at: now)
                        )
                        .appearTransition(delay: 0.18)
                    }
                    recentRow(summary: summary)
                        .appearTransition(delay: 0.24)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.play(.selection)
                        showQuickEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add entry")
                }
            }
            .refreshable {
                _ = await env.sync.syncAll()
            }
            .sheet(isPresented: $showQuickEntry) {
                QuickEntrySheet()
            }
            .sheet(isPresented: $showGlucoseEntry) {
                GlucoseEntrySheet()
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(summary: DashboardSummary, thresholds: GlucoseThresholds, unit: GlucoseUnit) -> some View {
        VStack(spacing: 14) {
            if let current = summary.current {
                let zone = thresholds.zone(forMgdL: current.valueMgdL)
                Button {
                    Haptics.play(.light)
                    showGlucoseEntry = true
                } label: {
                    VStack(spacing: 12) {
                        GlucoseGaugeRing(
                            mgdL: current.valueMgdL,
                            zone: zone,
                            unit: unit,
                            trend: current.trend
                        )
                        ZonePill(zone: zone)
                    }
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityHint("Opens glucose entry")

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        ProvenanceBadge(source: current.source)
                        Text(updatedText(summary: summary))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if summary.isStale {
                        Label("Stale reading", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(Theme.zoneWarning)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .accessibilityElement(children: .combine)

                if let warning = projectionWarning(summary: summary, thresholds: thresholds) {
                    warningChip(warning)
                }
            } else {
                Button {
                    Haptics.play(.light)
                    showGlucoseEntry = true
                } label: {
                    EmptyStateView(
                        systemImage: "drop",
                        title: "No glucose yet",
                        message: "Add a reading or connect a sensor to see your day."
                    )
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityHint("Opens glucose entry")
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 26, padding: 20)
        // Animate the stale / prediction chips in and out as new readings land.
        .animation(.smooth(duration: 0.3), value: summary.current?.valueMgdL)
    }

    private func updatedText(summary: DashboardSummary) -> String {
        guard let minutes = summary.minutesSinceUpdate else { return "Updated recently" }
        if minutes <= 0 { return "Updated just now" }
        return "Updated \(minutes) min ago"
    }

    // MARK: - Predictive warning

    private enum ProjectionWarning { case low(Int), high(Int) }

    /// Projects the current velocity to the next threshold and warns when a low
    /// or high is due within ~45 minutes.
    private func projectionWarning(summary: DashboardSummary, thresholds: GlucoseThresholds) -> ProjectionWarning? {
        guard !summary.isStale, let velocity = summary.velocity, let current = summary.current else { return nil }
        let mgdL = current.valueMgdL
        let slope = velocity.mgdLPerMinute
        let horizon = 45.0

        if slope < 0, mgdL > thresholds.targetLower,
           let minutes = GlucoseTrendAnalyzer.minutesToReach(thresholds.targetLower, from: mgdL, velocityPerMinute: slope),
           minutes <= horizon {
            return .low(Int(minutes.rounded()))
        }
        if slope > 0, mgdL < thresholds.targetUpper,
           let minutes = GlucoseTrendAnalyzer.minutesToReach(thresholds.targetUpper, from: mgdL, velocityPerMinute: slope),
           minutes <= horizon {
            return .high(Int(minutes.rounded()))
        }
        return nil
    }

    private func warningChip(_ warning: ProjectionWarning) -> some View {
        let text: Text
        let tint: Color
        switch warning {
        case .low(let minutes): text = Text("Low predicted in ~\(minutes) min"); tint = Theme.zoneWarning
        case .high(let minutes): text = Text("High predicted in ~\(minutes) min"); tint = Theme.zoneHigh
        }
        return Label { text } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: .capsule)
            .accessibilityElement(children: .combine)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear { Haptics.play(.warning) }
    }

    // MARK: - Trend

    @ViewBuilder
    private func trendSection(summary: DashboardSummary, thresholds: GlucoseThresholds, unit: GlucoseUnit) -> some View {
        SectionCard("Last 3 hours", systemImage: "waveform.path.ecg") {
            if let velocity = summary.velocity, let current = summary.current {
                velocityLine(velocity, currentMgdL: current.valueMgdL, unit: unit)
            }
            if summary.recent.isEmpty {
                EmptyStateView(
                    systemImage: "chart.xyaxis.line",
                    title: "No recent readings",
                    message: "Readings from the last three hours appear here."
                )
            } else {
                GlucoseTrendChart(
                    readings: summary.recent,
                    thresholds: thresholds,
                    unit: unit,
                    compact: false
                )
            }
        }
    }

    private func velocityLine(_ velocity: GlucoseVelocity, currentMgdL: Double, unit: GlucoseUnit) -> some View {
        let projected = velocity.projectedMgdL(from: currentMgdL, minutes: 15)
        let rateValue = unit.fromMgdL(velocity.mgdLPerMinute)
        let rate = rateValue.formatted(.number.precision(.fractionLength(unit == .mgdL ? 1 : 2)))
        let rateText = "\(rateValue > 0 ? "+" : "")\(rate) \(unit.rawValue)/min"
        return HStack(spacing: 8) {
            Image(systemName: velocity.trend.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(velocity.trend.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text(rateText)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("~\(GlucoseFormatting.string(mgdL: projected, unit: unit)) in 15 min")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(velocity.trend.label), \(rateText), projected \(GlucoseFormatting.labeled(mgdL: projected, unit: unit)) in 15 minutes")
    }

    // MARK: - Today's time in range

    private func todayCard(_ stats: PeriodStatistics) -> some View {
        let pct = (stats.timeInRange * 100).formatted(.number.precision(.fractionLength(0))) + "%"
        return SectionCard("Today's time in range", systemImage: "target") {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        todayBand(geo, stats.timeBelowRange, Theme.zoneWarning)
                        todayBand(geo, stats.timeInRange, Theme.zoneInRange)
                        todayBand(geo, stats.timeAboveRange, Theme.zoneHigh)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 14)

                HStack {
                    Text("\(pct) in range")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.zoneInRange)
                    Spacer()
                    Text("\(stats.readingCount) readings")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today's time in range \(pct), \(stats.readingCount) readings")
        }
    }

    private func todayBand(_ geo: GeometryProxy, _ fraction: Double, _ color: Color) -> some View {
        color.frame(width: max(geo.size.width * fraction, fraction > 0 ? 2 : 0))
    }

    // MARK: - On board (insulin + carbs)

    private func onBoardCard(iob: Double, cob: Double) -> some View {
        SectionCard("On board", systemImage: "chart.line.downtrend.xyaxis") {
            HStack(spacing: 18) {
                onBoardMetric(value: iob.formatted(.number.precision(.fractionLength(1))), unit: "U", label: "Insulin", tint: Theme.accent)
                Divider().frame(height: 34).overlay(Theme.hairline)
                onBoardMetric(value: cob.formatted(.number.precision(.fractionLength(0))), unit: "g", label: "Carbs", tint: Theme.zoneHigh)
                Spacer()
                NavigationLink {
                    BolusCalculatorView()
                } label: {
                    Label("Calculator", systemImage: "syringe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func onBoardMetric(value: String, unit: String, label: String, tint: Color = Theme.accent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Recent entries

    @ViewBuilder
    private func recentRow(summary: DashboardSummary) -> some View {
        HStack(spacing: 12) {
            insulinTile(summary.lastInsulin)
            mealTile(summary.lastMeal)
            activityTile(summary.lastActivity)
        }
    }

    private func insulinTile(_ dose: InsulinDose?) -> some View {
        StatTile(
            title: "Insulin",
            value: dose.map { "\($0.units.formatted()) U" } ?? "—",
            caption: dose.map { "\(dashboardRelativeText($0.timestamp)) · \($0.insulinType.label)" } ?? "No doses",
            tint: Theme.accent,
            systemImage: "syringe.fill"
        )
    }

    private func mealTile(_ meal: CarbEntry?) -> some View {
        StatTile(
            title: "Meal",
            value: meal.map { "\($0.grams.formatted()) g" } ?? "—",
            caption: meal.map { "\($0.mealType.label) · \(dashboardRelativeText($0.timestamp))" } ?? "No meals",
            tint: Theme.zoneHigh,
            systemImage: "fork.knife"
        )
    }

    private func activityTile(_ session: ActivityEntry?) -> some View {
        StatTile(
            title: "Activity",
            value: session.map { "\($0.durationMinutes) min" } ?? "—",
            caption: session.map { "\($0.activityType.label) · \(dashboardRelativeText($0.startTimestamp))" } ?? "No activity",
            tint: Theme.zoneInRange,
            systemImage: "figure.walk"
        )
    }
}

/// Human-friendly relative time ("5 min ago") for the dashboard's recent tiles.
/// Free function so it stays outside any actor isolation and is trivially reused.
private func dashboardRelativeText(_ date: Date, relativeTo now: Date = Date()) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
}

#Preview {
    let env = AppEnvironment.preview()
    return DashboardView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
