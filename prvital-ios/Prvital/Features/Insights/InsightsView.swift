import SwiftUI
import SwiftData

/// Insights — the analytics home. A ranked "Insights" feed pins the app's most
/// important patterns to the top (surfaced by `InsightFeed`), and a segmented
/// control flips between the visual `ChartsView` and the numeric
/// `StatisticsView`, while the toolbar offers a push to `ExportView` (share a
/// report) and to the full `HistoryView` ledger.
///
/// Both child screens share the same time-window vocabulary via
/// `InsightsInterval`, which is declared here so every Insights file can use it.
struct InsightsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var section: InsightsSection = .charts
    @State private var showingWeeklyDigest = false

    // Records feeding the ranked feed. Plain `@Query`s, filtered to a recent
    // window in `insightCards` so the surfaced patterns stay current.
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var glucose: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]

    /// The last 30 days — enough history for the analyzers, recent enough to act on.
    private var feedRange: ClosedRange<Date> { InsightsInterval.month.dateRange() }

    /// The ranked, capped feed. Pure aggregation lives in `InsightFeed`; the view
    /// only filters to the window and renders.
    private var insightCards: [InsightCard] {
        InsightFeed.build(
            readings: glucose.filter { $0.isActive && feedRange.contains($0.timestamp) },
            insulin: insulin.filter { feedRange.contains($0.timestamp) },
            carbs: carbs.filter { feedRange.contains($0.timestamp) },
            activity: activity.filter { feedRange.contains($0.startTimestamp) },
            thresholds: env.preferences.thresholds
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !insightCards.isEmpty {
                    InsightsFeedSection(cards: insightCards)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                }

                Picker("View", selection: $section) {
                    ForEach(InsightsSection.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .onChange(of: section) { _, _ in Haptics.play(.selection) }

                switch section {
                case .charts: ChartsView()
                case .statistics: StatisticsView()
                case .agp: AGPReportView()
                }
            }
            .prvitalTabBackground()
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        PlainLanguageSummaryView()
                    } label: {
                        Image(systemName: "text.quote")
                    }
                    .accessibilityLabel("In plain words")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.play(.selection)
                        showingWeeklyDigest = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .accessibilityLabel("Week in review")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExportView()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export a report")
                }
            }
            .sheet(isPresented: $showingWeeklyDigest) { WeeklyDigestView() }
        }
    }
}

// MARK: - Insights feed

/// The pinned "Insights" card, holding a horizontally scrolling row of the top
/// ranked findings. Uses the shared `SectionCard` so it matches the rest of the
/// Insights screen, Clarity-style: compact, tappable pattern tiles.
private struct InsightsFeedSection: View {
    let cards: [InsightCard]

    var body: some View {
        SectionCard("Insights", systemImage: "sparkles") {
            // Paged slides with index dots (per device feedback) instead of a
            // horizontal scroll that cropped the next tile mid-word.
            TabView {
                ForEach(cards) { card in
                    InsightCardView(card: card)
                        .padding(.bottom, 26)   // keep the dots off the tile
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 182)
            .accessibilityLabel("Top insights")
        }
    }
}

/// A single tappable insight tile. The tap gives haptic feedback; the tint and
/// icon come straight from the pure `InsightCard`.
private struct InsightCardView: View {
    let card: InsightCard

    var body: some View {
        Button {
            Haptics.play(.selection)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: card.systemImage)
                        .font(.headline)
                        .foregroundStyle(card.tint.color)
                        .frame(width: 34, height: 34)
                        .background(card.tint.color.opacity(0.16), in: .circle)
                    Spacer(minLength: 0)
                }
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(14)
            .frame(height: 148)
            .background(card.tint.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(card.tint.color.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title). \(card.detail)")
    }
}

/// Maps a UI-agnostic `InsightTint` to a `Theme` glucose-zone colour. Kept in the
/// view layer so `InsightFeed` stays free of SwiftUI.
private extension InsightTint {
    var color: Color {
        switch self {
        case .critical: return Theme.zoneCritical
        case .warning: return Theme.zoneWarning
        case .high: return Theme.zoneHigh
        case .positive: return Theme.zoneInRange
        case .neutral: return Theme.accent
        }
    }
}

/// The two panes of the Insights screen.
private enum InsightsSection: String, CaseIterable, Identifiable {
    case charts, statistics, agp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charts: return String(localized: "Charts")
        case .statistics: return String(localized: "Statistics")
        case .agp: return String(localized: "AGP")
        }
    }
}

/// The shared time window used across every Insights screen. Each case yields a
/// closed date range ending *now* and starting one interval earlier — the domain
/// the charts, statistics and exports all filter to.
enum InsightsInterval: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year: return String(localized: "Year")
        }
    }

    /// A human phrase for the window, used as the export period label.
    var periodLabel: String {
        switch self {
        case .day: return String(localized: "Last 24 hours")
        case .week: return String(localized: "Last 7 days")
        case .month: return String(localized: "Last 30 days")
        case .year: return String(localized: "Last 12 months")
        }
    }

    /// A closed range `[start, now]` where `start` is `now` minus one interval.
    func dateRange(now: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let start: Date
        switch self {
        case .day:   start = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:  start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .year:  start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
        return min(start, now)...now
    }

    /// The equal-length window immediately before `dateRange`, computed
    /// calendar-consistently (e.g. the month before the current month), used for
    /// period-over-period comparison.
    func previousDateRange(now: Date = Date()) -> ClosedRange<Date> {
        let currentStart = dateRange(now: now).lowerBound
        let previousStart = dateRange(now: currentStart).lowerBound
        return min(previousStart, currentStart)...currentStart
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return InsightsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}

#Preview("Insights feed") {
    let cards: [InsightCard] = [
        InsightCard(id: "pattern-overnight-frequentLow", title: "Often low overnight",
                    detail: "18% of overnight readings are below range",
                    systemImage: "arrow.down.circle.fill", severity: .critical, tint: .critical, date: nil, priority: 0.18),
        InsightCard(id: "rebound", title: "Rebound highs after lows",
                    detail: "Glucose spiked high after a low 4 times — watch for over-treating lows",
                    systemImage: "arrow.up.arrow.down", severity: .high, tint: .warning, date: Date(), priority: 0.6),
        InsightCard(id: "meal-breakfast", title: "Breakfast spikes +82 mg/dL",
                    detail: "Peaks about 55 min after eating, over 6 meals",
                    systemImage: "sunrise", severity: .low, tint: .high, date: Date(), priority: 0.68),
        InsightCard(id: "activity", title: "Activity lowers your glucose",
                    detail: "Glucose drops about 28 mg/dL after activity, across 5 sessions",
                    systemImage: "figure.walk.motion", severity: .informational, tint: .positive, date: Date(), priority: 0.47),
    ]
    return VStack {
        InsightsFeedSection(cards: cards)
            .padding()
        Spacer()
    }
    .background(Theme.background)
}
