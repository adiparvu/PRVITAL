import SwiftUI
import SwiftData

/// The "Daily goals" screen: three activity-style rings for today (In range /
/// Active / Sensor), a labelled breakdown of each, and a live status panel for
/// the connected data sources. Opened from the Dashboard's rings card.
///
/// Reads are scoped to the last 24 hours so the rings and the source-freshness
/// line stay cheap even with months of history in the store.
struct DailyGoalsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var readings: [GlucoseReading]
    @Query private var activity: [ActivityEntry]

    @State private var showGoalsEditor = false
    /// Today's Apple Health exercise minutes (the Watch's green ring), so the
    /// Active ring reflects all-day movement, not only logged workouts.
    @State private var healthActiveMinutes = 0

    init() {
        let windowStart = Calendar.current.date(byAdding: .hour, value: -24, to: Date())
            ?? Date().addingTimeInterval(-24 * 3600)
        _readings = Query(
            filter: #Predicate<GlucoseReading> { $0.timestamp >= windowStart },
            sort: \.timestamp, order: .reverse
        )
        _activity = Query(
            filter: #Predicate<ActivityEntry> { $0.startTimestamp >= windowStart },
            sort: \.startTimestamp, order: .reverse
        )
    }

    private var rings: DailyRings {
        DailyRings.make(
            readings: readings,
            activity: activity,
            thresholds: env.preferences.thresholds,
            inRangeGoalFraction: env.preferences.glucoseGoals.targetTIRFraction,
            activeGoalMinutes: env.preferences.ringGoals.activeMinutesGoal,
            coverageGoalFraction: env.preferences.ringGoals.coverageGoalFraction,
            healthExerciseMinutes: healthActiveMinutes
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ringsHeader(rings)
                    .appearTransition(delay: 0)
                legendCard(rings)
                    .appearTransition(delay: 0.06)
                sourcesCard
                    .appearTransition(delay: 0.12)
            }
            .padding()
        }
        .prvitalTabBackground()
        .navigationTitle("Daily goals")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let minutes = (await env.healthKit.dailyMetric(.exercise, days: 1)).last?.value ?? 0
            healthActiveMinutes = Int(minutes.rounded())
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.play(.selection)
                    showGoalsEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Edit ring goals")
            }
        }
        .sheet(isPresented: $showGoalsEditor) {
            RingGoalsEditorSheet()
        }
    }

    // MARK: - Rings header

    private func ringsHeader(_ rings: DailyRings) -> some View {
        VStack(spacing: 14) {
            ActivityRingsGauge(rings: rings)
            VStack(spacing: 3) {
                Text(headline(for: rings))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline(for: rings))
    }

    private func headline(for rings: DailyRings) -> String {
        guard rings.hasGlucose else { return String(localized: "No readings yet today") }
        switch rings.metCount {
        case 3: return String(localized: "All three rings closed — great day!")
        case 0: return String(localized: "Let's close your rings")
        default: return String(localized: "\(rings.metCount) of 3 rings closed")
        }
    }

    // MARK: - Legend

    private func legendCard(_ rings: DailyRings) -> some View {
        SectionCard("Your rings", systemImage: "circle.circle") {
            VStack(spacing: 14) {
                RingLegendRow(
                    kind: .inRange,
                    valueText: percent(rings.inRangeFraction),
                    goalText: String(localized: "Goal \(percent(rings.inRangeGoalFraction))"),
                    progress: rings.inRangeProgress,
                    met: rings.inRangeMet
                )
                RingLegendRow(
                    kind: .active,
                    valueText: String(localized: "\(rings.activeMinutes) min"),
                    goalText: String(localized: "Goal \(rings.activeGoalMinutes) min"),
                    progress: rings.activeProgress,
                    met: rings.activeMet
                )
                RingLegendRow(
                    kind: .sensor,
                    valueText: percent(rings.coverageFraction),
                    goalText: String(localized: "Goal \(percent(rings.coverageGoalFraction))"),
                    progress: rings.coverageProgress,
                    met: rings.coverageMet
                )
            }
        }
    }

    private func percent(_ fraction: Double) -> String {
        (fraction * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    // MARK: - Sources status

    private var sourcesCard: some View {
        let latest = readings.first  // most recent within the 24h window
        return SectionCard("Sources", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(spacing: 14) {
                SourceFreshnessRow(latest: latest)
                Divider().overlay(Theme.hairline)
                ForEach(env.registry.orderedSources, id: \.source) { source in
                    SourceStatusRow(source: source)
                }
                NavigationLink {
                    SourcesSettingsView()
                } label: {
                    HStack {
                        Text("Manage sources")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Legend row

/// One ring's breakdown: icon, title, value against its goal, a mini progress
/// bar, and a check once the ring is closed.
private struct RingLegendRow: View {
    let kind: RingKind
    let valueText: String
    let goalText: String
    let progress: Double
    let met: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(kind.tint)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if met {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(kind.tint)
                    }
                    Spacer()
                    Text(valueText)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(kind.tint)
                    Text(goalText)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                MiniProgressBar(progress: progress, tint: kind.tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.accessibilityTitle), \(valueText), \(goalText)\(met ? String(localized: ", complete") : "")")
    }
}

/// A thin, rounded progress track used by the ring legend rows.
private struct MiniProgressBar: View {
    let progress: Double
    let tint: Color

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: geo.size.width * (appeared ? clamped : 0))
            }
        }
        .frame(height: 6)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.smooth(duration: 0.6)) { appeared = true } }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sources rows

/// The "how fresh is my data" line: minutes since the most recent reading, with
/// a colour that goes amber then red as the data ages.
private struct SourceFreshnessRow: View {
    let latest: GlucoseReading?

    private var minutesAgo: Int? {
        latest.map { max(0, Int(Date().timeIntervalSince($0.timestamp) / 60)) }
    }

    private var tint: Color {
        guard let minutesAgo else { return Theme.textTertiary }
        if minutesAgo <= 10 { return Theme.zoneInRange }
        if minutesAgo <= 30 { return Theme.zoneHigh }
        return Theme.zoneCritical
    }

    private var detail: String {
        guard let minutesAgo, let latest else { return String(localized: "Waiting for the first reading") }
        let age: String = minutesAgo < 1
            ? String(localized: "just now")
            : String(localized: "\(minutesAgo) min ago")
        return String(localized: "\(latest.source.displayName) · \(age)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest reading")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Circle().fill(tint).frame(width: 8, height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest reading, \(detail)")
    }
}

/// A compact connection-state row for one source: name, a status dot and label.
private struct SourceStatusRow: View {
    let source: GlucoseSource

    private var descriptor: (label: String, color: Color) {
        switch source.connectionState {
        case .connected: return (String(localized: "Connected"), Theme.zoneInRange)
        case .connecting: return (String(localized: "Connecting…"), Theme.zoneHigh)
        case .needsAuthorization: return (String(localized: "Needs authorization"), Theme.zoneHigh)
        case .notConnected: return (String(localized: "Not connected"), Theme.textTertiary)
        case .unavailable: return (String(localized: "Unavailable"), Theme.textTertiary)
        case .failed(let message):
            return (message.isEmpty ? String(localized: "Connection failed") : message, Theme.zoneCritical)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.source.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(source.displayName)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(descriptor.color).frame(width: 7, height: 7)
                Text(descriptor.label)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.displayName), \(descriptor.label)")
    }
}

// MARK: - Ring goals editor

/// Adjusts the two ring-specific goals (active minutes, sensor uptime). The
/// In-range ring shares the Time-in-Range goal from the Goals editor, so a note
/// points there rather than duplicating the control.
struct RingGoalsEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = env.preferences
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $preferences.ringGoals.activeMinutesGoal, in: 10...180, step: 5) {
                        HStack {
                            Label {
                                Text("Active minutes")
                            } icon: {
                                Image(systemName: RingKind.active.symbol).foregroundStyle(RingKind.active.tint)
                            }
                            Spacer()
                            Text("\(preferences.ringGoals.activeMinutesGoal) min")
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Active ring")
                } footer: {
                    Text("Your daily movement target. Logged workouts and Apple Health activity both count toward it.")
                }

                Section {
                    Stepper(value: $preferences.ringGoals.coverageGoalPercent, in: 50...100, step: 5) {
                        HStack {
                            Label {
                                Text("Sensor uptime")
                            } icon: {
                                Image(systemName: RingKind.sensor.symbol).foregroundStyle(RingKind.sensor.tint)
                            }
                            Spacer()
                            Text("\(preferences.ringGoals.coverageGoalPercent.formatted(.number.precision(.fractionLength(0))))%")
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Sensor ring")
                } footer: {
                    Text("How much of the day you aim to have CGM data for. Consensus calls 70% or more reliable for statistics.")
                }

                Section {
                    HStack {
                        Label {
                            Text("In range")
                        } icon: {
                            Image(systemName: RingKind.inRange.symbol).foregroundStyle(RingKind.inRange.tint)
                        }
                        Spacer()
                        Text("\(preferences.glucoseGoals.targetTIRPercent.formatted(.number.precision(.fractionLength(0))))%")
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                } footer: {
                    Text("The In-range ring uses your Time-in-Range goal, which you set under Goals on the Dashboard.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Ring goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { DailyGoalsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
