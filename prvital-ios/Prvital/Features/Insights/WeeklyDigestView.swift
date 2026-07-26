import SwiftUI
import SwiftData

/// The Monday "week in review" sheet: a digest of the last full Monday–Sunday
/// week — headline, time-in-range ring with the change vs the week before, the
/// key numbers, best & toughest day, streak, and the week's top insight cards.
///
/// All computation lives in the pure `WeeklyDigest` composer; this view filters
/// nothing itself beyond handing the queried records over, then formats and
/// renders. A footer toggle arms the repeating Monday-morning notification via
/// `WeeklyDigestScheduler`.
struct WeeklyDigestView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]

    init() {
        // The digest covers the past week; a two-week window is plenty and keeps
        // it from loading all history.
        let cutoff = Calendar.current.date(byAdding: .day, value: -16, to: Date())
            ?? Date().addingTimeInterval(-16 * 86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
    }

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    /// The digest for the last full week, computed on demand — `nil` when that
    /// week has readings on fewer than 3 days.
    private var summary: WeeklyDigestSummary? {
        WeeklyDigest.compose(readings: glucose, thresholds: thresholds)
    }

    /// The digested week as a date interval, for filtering the insight feed.
    private var week: DateInterval { WeeklyDigest.lastFullWeek(before: Date()) }

    /// The top few ranked insight cards, rebuilt over the digest week only so
    /// the highlights describe the same days as the numbers above them.
    private var weekCards: [InsightCard] {
        let range = week
        let cards = InsightFeed.build(
            readings: glucose.filter { $0.isActive && range.start <= $0.timestamp && $0.timestamp < range.end },
            insulin: insulin.filter { range.start <= $0.timestamp && $0.timestamp < range.end },
            carbs: carbs.filter { range.start <= $0.timestamp && $0.timestamp < range.end },
            activity: activity.filter { range.start <= $0.startTimestamp && $0.startTimestamp < range.end },
            thresholds: thresholds
        )
        return Array(cards.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let summary {
                        heroCard(summary).appearTransition(delay: 0)
                        numbersCard(summary).appearTransition(delay: 0.06)
                        if summary.bestDay != nil || summary.toughestDay != nil {
                            bestToughestCard(summary).appearTransition(delay: 0.12)
                        }
                        if !weekCards.isEmpty {
                            highlightsCard.appearTransition(delay: 0.18)
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "calendar.badge.clock",
                            title: "No digest yet",
                            message: "Your week in review covers the last full Monday–Sunday week. It appears once that week has readings on at least 3 days."
                        )
                        .glassCard()
                    }

                    notificationCard
                    insightNotificationCard
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Week in review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Hero — headline, ring & delta

    private func heroCard(_ summary: WeeklyDigestSummary) -> some View {
        SectionCard("Last week", systemImage: "calendar.badge.clock",
                    accessory: AnyView(
                        Text(weekLabel(summary))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    )) {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 20) {
                    DigestRing(progress: summary.timeInRange, centerText: percent(summary.timeInRange))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time in range")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        deltaBadge(summary.timeInRangeDelta)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(summary.headline). Time in range \(percent(summary.timeInRange)). \(deltaText(summary.timeInRangeDelta))"
            )
        }
    }

    @ViewBuilder
    private func deltaBadge(_ delta: Double?) -> some View {
        if let delta {
            let points = Int((delta * 100).rounded())
            if points == 0 {
                Text("Same as the week before")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: points > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.weight(.bold))
                    Text("\(abs(points)) pts vs week before")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(points > 0 ? Theme.zoneInRange : Theme.zoneCritical)
            }
        } else {
            Text("No data for the week before")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func deltaText(_ delta: Double?) -> String {
        guard let delta else { return "No data for the week before." }
        let points = Int((delta * 100).rounded())
        if points == 0 { return "Same as the week before." }
        return points > 0
            ? "Up \(points) points vs the week before."
            : "Down \(-points) points vs the week before."
    }

    // MARK: The numbers

    private func numbersCard(_ summary: WeeklyDigestSummary) -> some View {
        SectionCard("The numbers", systemImage: "number") {
            VStack(alignment: .leading, spacing: 12) {
                statRow("Average", GlucoseFormatting.labeled(mgdL: summary.averageMgdL, unit: unit),
                        systemImage: "drop.fill", tint: Theme.accent)
                statRow("Est. A1c (GMI)",
                        summary.gmiPercent.formatted(.number.precision(.fractionLength(1))) + "%",
                        systemImage: "waveform.path.ecg", tint: Theme.accent)
                statRow("Readings", "\(summary.readingCount)",
                        systemImage: "chart.dots.scatter", tint: Theme.textSecondary)
                statRow("Lows", "\(summary.lowsCount)",
                        systemImage: "arrow.down.circle", tint: Theme.zoneCritical)
                statRow("Highs", "\(summary.highsCount)",
                        systemImage: "arrow.up.circle", tint: Theme.zoneHigh)
                statRow("In-range day streak",
                        summary.streakDays == 1 ? "1 day" : "\(summary.streakDays) days",
                        systemImage: "flame.fill", tint: Theme.zoneWarning)
            }
        }
    }

    private func statRow(_ title: LocalizedStringKey, _ value: String,
                         systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Best & toughest day

    private func bestToughestCard(_ summary: WeeklyDigestSummary) -> some View {
        SectionCard("Best & toughest day", systemImage: "calendar.badge.clock") {
            HStack(spacing: 16) {
                if let best = summary.bestDay {
                    dayColumn(title: "Best day", day: best, tint: Theme.zoneInRange)
                }
                if summary.bestDay != nil && summary.toughestDay != nil {
                    Divider().frame(height: 52).overlay(Theme.hairline)
                }
                if let toughest = summary.toughestDay {
                    dayColumn(title: "Toughest day", day: toughest, tint: Theme.zoneHigh)
                }
                Spacer()
            }
        }
    }

    private func dayColumn(title: LocalizedStringKey, day: WeeklyDigestDay, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(percent(day.timeInRange))
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
            Text(day.day.formatted(.dateTime.weekday(.wide)))
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Highlights (insight cards for the week)

    private var highlightsCard: some View {
        SectionCard("Highlights", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(weekCards) { card in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: card.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(card.tint.digestColor)
                            .frame(width: 30, height: 30)
                            .background(card.tint.digestColor.opacity(0.16), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(card.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(card.title). \(card.detail)")
                }
            }
        }
    }

    // MARK: Monday notification toggle

    private var notificationCard: some View {
        @Bindable var prefs = env.preferences
        return SectionCard("Monday reminder", systemImage: "bell.badge") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Notify me Mondays at 9 AM", isOn: $prefs.weeklyDigestEnabled)
                    .tint(Theme.accent)
                Text("A quiet local notification when your week in review is ready. The digest itself is computed on your device when you open it.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: prefs.weeklyDigestEnabled) { _, enabled in
            Haptics.play(.selection)
            if enabled {
                Task { _ = await env.notifications.requestAuthorization() }
            }
            WeeklyDigestScheduler().update(enabled: enabled)
        }
    }

    /// The Sunday-evening "insight of the week" opt-in. Unlike the Monday
    /// invite, its notification carries the top pattern's headline — so the
    /// footer says exactly that, and it stays a separate switch.
    private var insightNotificationCard: some View {
        @Bindable var prefs = env.preferences
        return SectionCard("Sunday insight", systemImage: "lightbulb.max") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Notify me Sundays at 7 PM", isOn: $prefs.weeklyInsightEnabled)
                    .tint(Theme.accent)
                Text("Carries the week's main pattern as its headline — for example \u{201C}Often low overnight\u{201D}, never a number. Composed on your device.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: prefs.weeklyInsightEnabled) { _, enabled in
            Haptics.play(.selection)
            if enabled {
                Task { _ = await env.notifications.requestAuthorization() }
            }
            env.rearmWeeklyInsight()
        }
    }

    // MARK: Formatting

    /// "Mar 9 – Mar 15" for the digested Monday–Sunday week.
    private func weekLabel(_ summary: WeeklyDigestSummary) -> String {
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: summary.weekStart) ?? summary.weekStart
        let start = summary.weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = sunday.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    /// Percentage rendered as `value * 100` rounded, matching the rest of Insights.
    private func percent(_ fraction: Double) -> String {
        "\((fraction * 100).rounded().formatted(.number.precision(.fractionLength(0))))%"
    }
}

// MARK: - Ring

/// A large progress ring for the digest hero, in the visual language of the
/// dashboard's goal ring (which is private to `DashboardView`, hence this small
/// local sibling).
private struct DigestRing: View {
    let progress: Double
    let centerText: String
    var diameter: CGFloat = 104

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            Circle()
                .trim(from: 0, to: appeared ? clamped : 0)
                .stroke(Theme.zoneInRange.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: clamped)
            VStack(spacing: 1) {
                Text(centerText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("in range")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appeared = true } }
        }
        .accessibilityHidden(true)
    }
}

/// Maps a UI-agnostic `InsightTint` to a `Theme` colour for the highlights rows.
/// (The equivalent extension in `InsightsView` is private to that file.)
private extension InsightTint {
    var digestColor: Color {
        switch self {
        case .critical: return Theme.zoneCritical
        case .warning: return Theme.zoneWarning
        case .high: return Theme.zoneHigh
        case .positive: return Theme.zoneInRange
        case .neutral: return Theme.accent
        }
    }
}

// MARK: - Previews

/// A fresh in-memory container so these previews never pollute the shared
/// `PersistenceController.previewContainer` other screens' previews rely on.
@MainActor
private func makeDigestPreviewContainer() -> ModelContainer {
    let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    return try! ModelContainer(for: AppSchema.schema, configurations: [configuration])
}

#Preview {
    let container = makeDigestPreviewContainer()
    let env = AppEnvironment(modelContainer: container)
    // A smooth fortnight of hourly readings — a rougher comparison week, then a
    // better digest week — so the ring, delta and highlights all render.
    let context = container.mainContext
    let calendar = Calendar.current
    let week = WeeklyDigest.lastFullWeek(before: Date(), calendar: calendar)
    let start = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start
    var timestamp = start
    var i = 0
    while timestamp < week.end {
        let base: Double = timestamp < week.start ? 158 : 132
        let value = base + 46 * sin(Double(i) / 3.1)
        context.insert(GlucoseReading(valueMgdL: value, timestamp: timestamp, source: .manual))
        timestamp = calendar.date(byAdding: .hour, value: 1, to: timestamp) ?? week.end
        i += 1
    }
    return WeeklyDigestView()
        .environment(env)
        .modelContainer(container)
}

#Preview("Empty digest") {
    let container = makeDigestPreviewContainer()
    let env = AppEnvironment(modelContainer: container)
    return WeeklyDigestView()
        .environment(env)
        .modelContainer(container)
}
