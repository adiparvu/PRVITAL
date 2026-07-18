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

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero(summary: summary, thresholds: thresholds, unit: unit)
                    trendSection(summary: summary, thresholds: thresholds, unit: unit)
                    recentRow(summary: summary)
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
                .buttonStyle(.plain)
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
                    }
                }
                .accessibilityElement(children: .combine)
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
                .buttonStyle(.plain)
                .accessibilityHint("Opens glucose entry")
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 26, padding: 20)
    }

    private func updatedText(summary: DashboardSummary) -> String {
        guard let minutes = summary.minutesSinceUpdate else { return "Updated recently" }
        if minutes <= 0 { return "Updated just now" }
        return "Updated \(minutes) min ago"
    }

    // MARK: - Trend

    @ViewBuilder
    private func trendSection(summary: DashboardSummary, thresholds: GlucoseThresholds, unit: GlucoseUnit) -> some View {
        SectionCard("Last 3 hours", systemImage: "waveform.path.ecg") {
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
