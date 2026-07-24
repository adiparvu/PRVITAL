import SwiftUI
import SwiftData
import StoreKit

/// The Dashboard — the app's first screen. Shows the current glucose value as a
/// hero gauge, the last three hours as a trend chart, and the most recent
/// insulin / meal / activity at a glance. All reads are reactive `@Query`s that
/// are filtered and summarised in the view; the single write path is presenting
/// the shared entry editors.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.requestReview) private var requestReview

    // Bounded to a recent window (see `windowDays`) so the home screen stays
    // snappy even after a full-history import of 100k+ readings. Deep history
    // lives in the Journal and Insights tabs.
    @Query private var readings: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var medications: [MedicationDose]
    @Query private var ketones: [KetoneReading]
    @Query private var notes: [ObservationEntry]
    @Query(sort: \SensorSession.startDate, order: .reverse) private var sensorSessions: [SensorSession]
    @Environment(\.scenePhase) private var scenePhase
    // Session-only dismissal of the companion card: cleared when the app returns
    // to the foreground, so it comes back on the next open (as requested).
    @State private var companionDismissed = false

    /// How far back the dashboard reaches: enough for the 7-day forecast
    /// baseline and a reasonable custom trend range. The custom picker is
    /// capped to match so it can't ask for data the query didn't load.
    private static let windowDays = 21

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date())
            ?? Date().addingTimeInterval(-Double(Self.windowDays) * 86_400)
        _readings = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
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

    /// Earliest date the custom trend picker allows — matches the query window
    /// so the picker can't request data the bounded query never loaded.
    private var earliestTrendDate: Date {
        Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date()) ?? Date()
    }

    @State private var showQuickEntry = false
    @State private var showGlucoseEntry = false
    @State private var showGoalsEditor = false
    @State private var showRuleOf15 = false
    /// The quick-action row's active entry sheet (glucose / carbs / insulin / …).
    @State private var quickAction: DashboardQuickAction?
    @State private var syncFailure: String?
    @State private var trendRange: DashboardTrendRange = .threeHours
    @State private var showCustomRange = false
    @State private var customStart = Date().addingTimeInterval(-6 * 3600)
    @State private var customEnd = Date()
    /// Today's Apple Health exercise minutes (the Watch's green ring), read live so
    /// the Active ring and activity tile fill from all-day movement, not only
    /// logged workouts.
    @State private var healthActiveMinutes = 0

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
                    quickActionsRow()
                        .appearTransition(delay: 0.01)
                    if env.preferences.showDailyCompanion && !companionDismissed {
                        dailyCompanionCard(summary: summary, todayStats: todayStats, thresholds: thresholds)
                            .appearTransition(delay: 0.02)
                    }
                    if env.preferences.sickDayEnabled {
                        SickDayBanner()
                            .appearTransition(delay: 0.03)
                    } else {
                        let suggestion = SickDayAdvisor.evaluate(readings: readings)
                        if suggestion.shouldSuggest {
                            SickDaySuggestionBanner(averageMgdL: suggestion.averageMgdL, unit: unit)
                                .appearTransition(delay: 0.03)
                        }
                    }
                    trendSection(summary: summary, thresholds: thresholds, unit: unit)
                        .appearTransition(delay: 0.06)
                    contextualLessonCard(thresholds: thresholds)
                        .appearTransition(delay: 0.08)
                    if todayStats.hasGlucose {
                        todayCard(todayStats,
                                  forecast: tirForecast(thresholds: thresholds),
                                  goalFraction: env.preferences.glucoseGoals.targetTIRFraction)
                            .appearTransition(delay: 0.12)
                    }
                    if env.preferences.glucoseGoals.enabled {
                        goalsCard(todayStats, thresholds: thresholds)
                            .appearTransition(delay: 0.14)
                    }
                    if todayStats.hasGlucose {
                        ringsCard(thresholds: thresholds)
                            .appearTransition(delay: 0.16)
                    }
                    if let session = sensorSessions.first {
                        let sensorStatus = SensorSessionEvaluator.status(
                            start: session.startDate, kind: session.kind, now: Date())
                        if sensorStatus.phase != .active {
                            sensorBanner(session: session, status: sensorStatus)
                                .appearTransition(delay: 0.15)
                        }
                    }
                    let scheduleStatuses = glucoseScheduleStatuses
                    if !scheduleStatuses.isEmpty {
                        scheduleCard(scheduleStatuses)
                            .appearTransition(delay: 0.18)
                    }
                    if bolus.isEnabled && bolus.isValid {
                        let now = Date()
                        onBoardCard(
                            iob: InsulinMath.activeInsulin(doses: insulin, at: now, parameters: bolus),
                            cob: CarbMath.carbsOnBoard(entries: carbs, at: now)
                        )
                        .appearTransition(delay: 0.24)
                    }
                    TodayTimelineCard(
                        readings: readings, insulin: insulin, carbs: carbs, activity: activity,
                        medications: medications, ketones: ketones, notes: notes,
                        unit: unit, thresholds: thresholds
                    )
                    .appearTransition(delay: 0.28)
                    recentRow(summary: summary)
                        .appearTransition(delay: 0.30)
                }
                .padding()
            }
            .prvitalTabBackground()
            .navigationTitle("Today")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    companionDismissed = false
                    Task { await refreshHealthActivity() }
                }
            }
            .task { await refreshHealthActivity() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.play(.selection)
                        showGoalsEditor = true
                    } label: {
                        Image(systemName: "target")
                    }
                    .accessibilityLabel("Goals")
                    .accessibilityHint("Set your time-in-range and A1c goals")
                }
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
                // Surface genuine source/network failures (not "source not set up"
                // states, which are filtered out in SyncCoordinator) instead of
                // silently looking like "no new data".
                let report = await env.sync.syncAll()
                syncFailure = report.failures.isEmpty ? nil : report.failures.joined(separator: "\n")
            }
            .overlay(alignment: .top) {
                if let syncFailure {
                    SyncErrorBanner(message: syncFailure) {
                        withAnimation { self.syncFailure = nil }
                    }
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: syncFailure) {
                        // Auto-dismiss the non-blocking banner after a few seconds.
                        try? await Task.sleep(for: .seconds(6))
                        withAnimation { self.syncFailure = nil }
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: syncFailure)
            .sheet(isPresented: $showQuickEntry) {
                QuickEntrySheet()
            }
            .sheet(isPresented: $showGlucoseEntry) {
                GlucoseEntrySheet()
            }
            .sheet(isPresented: $showGoalsEditor) {
                GoalsEditorSheet()
            }
            .sheet(isPresented: $showRuleOf15) {
                RuleOf15Sheet()
            }
            .sheet(item: $quickAction) { action in
                switch action {
                case .glucose: GlucoseEntrySheet()
                case .carbs: CarbEntrySheet()
                case .insulin: InsulinEntrySheet()
                case .activity: ActivityEntrySheet()
                case .note: ObservationEntrySheet()
                }
            }
            .task {
                // Fold any freshly-earned achievements into the (monotonic) store
                // so the badge count stays current even without opening the gallery.
                AchievementStore().record(unlocked: AchievementEvaluator.unlocked(
                    AchievementInputsBuilder.make(
                        readings: readings, meals: carbs,
                        thresholds: thresholds,
                        goalFraction: env.preferences.glucoseGoals.targetTIRFraction)))

                // A day with data is a good moment: count it, and — sparingly,
                // at most once per app version after enough such moments — ask
                // for a rating. StoreKit may still choose to suppress the prompt.
                guard todayStats.hasGlucose else { return }
                RatingPrompter.registerPositiveMoment()
                if RatingPrompter.consumePromptOpportunity() {
                    requestReview()
                }
            }
        }
    }

    // MARK: - Quick actions

    /// The one-tap logging row — glucose, carbs, insulin, activity, note — each
    /// opening its entry sheet directly, so the most common action is never more
    /// than a single tap from the home screen.
    private func quickActionsRow() -> some View {
        HStack(spacing: 8) {
            quickActionButton(.glucose, icon: "drop.fill", tint: Theme.accent, label: "Glucose")
            quickActionButton(.carbs, icon: "fork.knife", tint: Theme.zoneHigh, label: "Carbs")
            quickActionButton(.insulin, icon: "syringe.fill", tint: Theme.accent, label: "Insulin")
            quickActionButton(.activity, icon: "figure.walk", tint: Theme.zoneInRange, label: "Activity")
            quickActionButton(.note, icon: "square.and.pencil", tint: Theme.textSecondary, label: "Note")
        }
    }

    private func quickActionButton(_ action: DashboardQuickAction, icon: String,
                                   tint: Color, label: LocalizedStringKey) -> some View {
        Button {
            Haptics.play(.light)
            quickAction = action
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 50, height: 50)
                    .background(tint.opacity(0.14), in: .circle)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Log a new entry")
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
                        ZonePill(zone: zone, plain: true)
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

                // The live "how am I right now?" vitals: IOB, COB, time since bolus,
                // time until insulin clears, time to the next reading.
                let vitals = LiveVitals.make(
                    latestReadingAt: current.timestamp,
                    sourceIsCGM: current.source.isCGM,
                    cgmCadenceMinutes: 5,
                    insulin: insulin, carbs: carbs,
                    bolus: env.preferences.bolusParameters)
                LiveVitalsStrip(vitals: vitals)
                    .animation(.snappy, value: vitals)

                if let warning = projectionWarning(summary: summary, thresholds: thresholds) {
                    warningChip(warning)
                }

                if zone.isHypo {
                    Button {
                        Haptics.play(.warning)
                        showRuleOf15 = true
                    } label: {
                        // Plain tinted text, no filled button — the zone colour and
                        // the medical-kit icon carry the urgency without a heavy
                        // orange bar dominating the hero.
                        Label("Treat low (Rule of 15)", systemImage: "cross.case.fill")
                            .font(.headline)
                            .foregroundStyle(zone.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    .accessibilityHint("Opens a guided low-glucose treatment")
                    .transition(.opacity)
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
        guard let minutes = summary.minutesSinceUpdate else { return String(localized: "Updated recently") }
        if minutes <= 0 { return String(localized: "Updated just now") }
        return String(localized: "Updated \(minutes) min ago")
    }

    // MARK: - Predictive warning

    private enum ProjectionWarning { case low(Int), high(Int) }

    /// Warns only when a low or high is *imminent* — heading across the target
    /// band within ~30 minutes on a genuine trend — so the chip appears just when
    /// it's actionable rather than lingering on every drift.
    private func projectionWarning(summary: DashboardSummary, thresholds: GlucoseThresholds) -> ProjectionWarning? {
        guard !summary.isStale, let velocity = summary.velocity, let current = summary.current,
              let projection = GlucoseTrendAnalyzer.imminentProjection(
                currentMgdL: current.valueMgdL,
                velocityPerMinute: velocity.mgdLPerMinute,
                thresholds: thresholds
              )
        else { return nil }
        switch projection.kind {
        case .low: return .low(projection.minutes)
        case .high: return .high(projection.minutes)
        }
    }

    private func warningChip(_ warning: ProjectionWarning) -> some View {
        let text: Text
        let tint: Color
        let icon: String
        switch warning {
        case .low(let minutes):
            text = Text("Low predicted in ~\(minutes) min"); tint = Theme.zoneWarning; icon = "arrow.down.forward"
        case .high(let minutes):
            text = Text("High predicted in ~\(minutes) min"); tint = Theme.zoneHigh; icon = "arrow.up.forward"
        }
        // Plain tinted text, no filled chip — the colour and arrow carry the
        // meaning without a capsule sitting under the gauge.
        return Label { text } icon: { Image(systemName: icon) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
            .onAppear { Haptics.play(.warning) }
    }

    // MARK: - Trend

    @ViewBuilder
    private func trendSection(summary: DashboardSummary, thresholds: GlucoseThresholds, unit: GlucoseUnit) -> some View {
        let windowReadings = trendReadings()
        return SectionCard(
            trendRange.titleKey,
            systemImage: "waveform.path.ecg",
            accessory: AnyView(trendRangeMenu)
        ) {
            // The most *local* velocity available — the tightest window (hence the
            // most precise recent rate) that still has enough points, so the line
            // stays put through a missed reading without smearing the rate more
            // than necessary.
            if let velocity = summary.isStale ? nil
                : GlucoseTrendAnalyzer.bestVelocity(summary.recent, now: summary.now),
               let current = summary.current {
                // A damped, IOB/COB-aware forecast with an honest range — see
                // GlucoseForecast — instead of a naive straight-line projection.
                let vitals = LiveVitals.make(
                    latestReadingAt: current.timestamp, sourceIsCGM: current.source.isCGM,
                    cgmCadenceMinutes: 5, insulin: insulin, carbs: carbs,
                    bolus: env.preferences.bolusParameters)
                let forecast = GlucoseForecast.project(
                    currentMgdL: current.valueMgdL, velocityMgdLPerMin: velocity.mgdLPerMinute,
                    iob: vitals.insulinOnBoard, cob: vitals.carbsOnBoard, horizonMinutes: 30)
                velocityLine(velocity, currentMgdL: current.valueMgdL, unit: unit, forecast: forecast)
            }
            if windowReadings.isEmpty {
                EmptyStateView(
                    systemImage: "chart.xyaxis.line",
                    title: "No readings in range",
                    message: "Readings for the selected range appear here."
                )
            } else {
                GlucoseTrendChart(
                    readings: windowReadings,
                    thresholds: thresholds,
                    unit: unit,
                    compact: false,
                    events: trendEvents(in: windowReadings),
                    visibleEventKinds: env.preferences.chartEventKinds,
                    eventKindsBinding: eventKindsBinding,
                    eventBand: true
                )
            }
        }
        .sheet(isPresented: $showCustomRange) { trendCustomRangeSheet }
    }

    /// Non-glucose events within the same span as the shown trend readings, so
    /// the markers line up with the visible curve.
    private func trendEvents(in readings: [GlucoseReading]) -> [ChartEvent] {
        guard let lo = readings.map(\.timestamp).min(),
              let hi = readings.map(\.timestamp).max() else { return [] }
        return ChartEvent.build(insulin: insulin, meals: carbs, medications: medications,
                                activity: activity, ketones: ketones, notes: notes)
            .filter { $0.date >= lo && $0.date <= hi }
    }

    private var eventKindsBinding: Binding<Set<ChartEventKind>> {
        Binding(get: { env.preferences.chartEventKinds },
                set: { env.preferences.chartEventKinds = $0 })
    }

    /// The active readings within the currently selected trend window.
    private func trendReadings() -> [GlucoseReading] {
        let active = readings.filter(\.isActive)
        switch trendRange {
        case .custom:
            let lo = min(customStart, customEnd)
            let hi = max(customStart, customEnd)
            return active.filter { $0.timestamp >= lo && $0.timestamp <= hi }
        default:
            let start = Date().addingTimeInterval(-trendRange.hours * 3600)
            return active.filter { $0.timestamp >= start }
        }
    }

    /// A contextual lesson: the Panou points you to the encyclopedia article that
    /// fits what your glucose just did — the connective tissue between the data and
    /// Învață. Hidden when there's nothing recent to teach from.
    @ViewBuilder
    private func contextualLessonCard(thresholds: GlucoseThresholds) -> some View {
        if let lesson = ContextualLesson.make(
                recentMgdL: recentMgdLForLesson(),
                targetLow: thresholds.targetLower,
                targetHigh: thresholds.targetUpper,
                hadRecentMeal: hadRecentMealForLesson(),
                dawnRiseLikely: dawnRiseLikelyForLesson()),
           let article = LearnLibrary.articles.first(where: { $0.id == lesson.articleID }) {
            NavigationLink {
                ArticleDetailView(article: article)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: article.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 46, height: 46)
                        .background(Theme.accentSoft, in: .circle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lessonReason(lesson.situation))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .textCase(.uppercase)
                        Text(LocalizedStringKey(article.title))
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(LocalizedStringKey(article.summary))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 20, padding: 14)
                .contentShape(.rect)
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private func lessonReason(_ situation: ContextualLesson.Situation) -> LocalizedStringKey {
        switch situation {
        case .recentLow:    return "Because you had a low earlier"
        case .postMealHigh: return "A high after eating — a carb refresher can help"
        case .dawnRise:     return "A morning rise — this may be why"
        case .recentHigh:   return "Because you had a high earlier"
        case .steady:       return "You've been steady — here's why that matters"
        }
    }

    /// The active glucose values (mg/dL) from the last six hours — the window the
    /// contextual lesson reasons over.
    private func recentMgdLForLesson() -> [Double] {
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        return readings.filter { $0.isActive && $0.timestamp >= cutoff }.map(\.valueMgdL)
    }

    /// Whether a meal was logged in the last three hours — used to attribute a
    /// recent high to carbs and point to the carb-counting lesson.
    private func hadRecentMealForLesson() -> Bool {
        let cutoff = Date().addingTimeInterval(-3 * 3600)
        return carbs.contains { $0.timestamp >= cutoff }
    }

    /// True in the early-morning window when the user has an established dawn
    /// pattern — so a pre-breakfast high is attributed to dawn rather than a
    /// generic high. Uses the same detector as Analize over the 21-day window.
    private func dawnRiseLikelyForLesson() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        guard (3..<10).contains(hour) else { return false }
        return DawnPhenomenonDetector.analyze(readings)?.isPresent == true
    }

    /// The top-right range picker (3h / 6h / 12h / 24h / custom).
    private var trendRangeMenu: some View {
        Menu {
            ForEach(DashboardTrendRange.allCases) { range in
                Button {
                    trendRange = range
                    if range == .custom { showCustomRange = true }
                } label: {
                    if range == trendRange {
                        Label(range.menuLabel, systemImage: "checkmark")
                    } else {
                        Text(range.menuLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(trendRange.shortLabel)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Time range")
        .accessibilityValue(trendRange.shortLabel)
    }

    private var trendCustomRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $customStart, in: earliestTrendDate...customEnd)
                DatePicker("To", selection: $customEnd, in: customStart...Date())
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCustomRange = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func velocityLine(_ velocity: GlucoseVelocity, currentMgdL: Double,
                              unit: GlucoseUnit, forecast: GlucoseForecast) -> some View {
        let rateValue = unit.fromMgdL(velocity.mgdLPerMinute)
        let rate = rateValue.formatted(.number.precision(.fractionLength(unit == .mgdL ? 1 : 2)))
        let rateText = "\(rateValue > 0 ? "+" : "")\(rate) \(unit.rawValue)/min"
        let projText = GlucoseFormatting.string(mgdL: forecast.projectedMgdL, unit: unit)
        let lowText = GlucoseFormatting.string(mgdL: forecast.lowMgdL, unit: unit)
        let highText = GlucoseFormatting.string(mgdL: forecast.highMgdL, unit: unit)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: velocity.trend.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(velocity.trend.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(rateText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("~\(projText) in \(forecast.horizonMinutes) min")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            Text("Likely \(lowText)–\(highText)")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Today's time in range

    private func todayCard(_ stats: PeriodStatistics, forecast: TIRForecast, goalFraction: Double) -> some View {
        let pct = (stats.timeInRange * 100).formatted(.number.precision(.fractionLength(0))) + "%"
        return SectionCard("Today's time in range", systemImage: "target") {
            VStack(alignment: .leading, spacing: 14) {
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

                // The end-of-day outlook, folded in so today's time-in-range lives
                // in one card instead of two adjacent ones.
                if forecast.hasData {
                    Divider().overlay(Theme.hairline)
                    forecastRow(forecast, goalFraction: goalFraction)
                }
            }
        }
    }

    private func todayBand(_ geo: GeometryProxy, _ fraction: Double, _ color: Color) -> some View {
        color.frame(width: max(geo.size.width * fraction, fraction > 0 ? 2 : 0))
    }

    // MARK: - Today's outlook (TIR forecast)

    /// Blends today's readings with the prior week to project how today's
    /// time-in-range is likely to finish.
    private func tirForecast(thresholds: GlucoseThresholds) -> TIRForecast {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let baselineStart = cal.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        let today = readings.filter { $0.timestamp >= startOfToday && $0.timestamp <= now }
        let baseline = readings.filter { $0.timestamp >= baselineStart && $0.timestamp < startOfToday }
        return TIRForecastEngine.forecast(
            today: today, baseline: baseline, thresholds: thresholds, now: now)
    }

    /// A gentle projection of today's end-of-day time-in-range: where it stands
    /// now, where it's heading, and how confident that estimate is. Supportive,
    /// never alarming.
    /// The end-of-day outlook row (now → projected + confidence), folded into the
    /// Today card so today's time-in-range isn't rendered across two cards.
    private func forecastRow(_ forecast: TIRForecast, goalFraction: Double) -> some View {
        let nowPct = (forecast.currentFraction * 100).formatted(.number.precision(.fractionLength(0)))
        let projPct = (forecast.projectedFraction * 100).formatted(.number.precision(.fractionLength(0)))
        let onTrack = goalFraction > 0 && forecast.projectedFraction >= goalFraction
        let note: String = goalFraction <= 0
            ? String(localized: "Based on today so far and your recent days.")
            : (onTrack
                ? String(localized: "On track to reach your goal today.")
                : String(localized: "A steady rest of the day can still lift this."))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                forecastFigure(title: "Now", value: "\(nowPct)%", tint: Theme.textPrimary)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
                forecastFigure(title: "Projected", value: "\(projPct)%",
                               tint: onTrack ? Theme.zoneInRange : Theme.accent)
                Spacer()
                confidenceBadge(forecast.confidence)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("End-of-day outlook. Now \(nowPct) percent in range, projected \(projPct) percent. \(confidenceLabel(forecast.confidence)) confidence. \(note)")
    }

    private func forecastFigure(title: LocalizedStringKey, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func confidenceBadge(_ confidence: TIRForecast.Confidence) -> some View {
        let label: LocalizedStringKey
        let color: Color
        switch confidence {
        case .high: label = "High confidence"; color = Theme.zoneInRange
        case .medium: label = "Medium confidence"; color = Theme.accent
        case .low: label = "Early estimate"; color = Theme.textTertiary
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func confidenceLabel(_ confidence: TIRForecast.Confidence) -> String {
        switch confidence {
        case .high: return String(localized: "High")
        case .medium: return String(localized: "Medium")
        case .low: return String(localized: "Low")
        }
    }

    // MARK: - Daily companion

    /// The supportive companion card. Composes today's control into a warm,
    /// non-judgmental message; the current streak is only mentioned when it's a
    /// real run (≥ 2 days).
    private func dailyCompanionCard(summary: DashboardSummary, todayStats: PeriodStatistics, thresholds: GlucoseThresholds) -> some View {
        let goalFraction = env.preferences.glucoseGoals.targetTIRFraction
        let streak = todayStats.hasGlucose
            ? StreakCalculator.evaluate(
                days: DailyBreakdown.perDay(readings, thresholds: thresholds),
                targetFraction: goalFraction).current
            : 0
        let message = DailyCompanion.message(
            hasGlucose: todayStats.hasGlucose,
            tirFraction: todayStats.timeInRange,
            goalFraction: goalFraction,
            currentZone: summary.isStale ? nil : summary.zone,
            streakDays: streak)
        return DailyCompanionCard(message: message) {
            withAnimation(.snappy) { companionDismissed = true }
        }
    }

    // MARK: - Daily rings

    /// A compact three-ring summary (In range / Active / Sensor) that opens the
    /// full Daily goals screen — where the rings are broken down and the data
    /// sources' live status is shown.
    private func ringsCard(thresholds: GlucoseThresholds) -> some View {
        let rings = DailyRings.make(
            readings: readings,
            activity: activity,
            thresholds: thresholds,
            inRangeGoalFraction: env.preferences.glucoseGoals.targetTIRFraction,
            activeGoalMinutes: env.preferences.ringGoals.activeMinutesGoal,
            coverageGoalFraction: env.preferences.ringGoals.coverageGoalFraction,
            healthExerciseMinutes: healthActiveMinutes
        )
        return NavigationLink {
            DailyGoalsView()
        } label: {
            HStack(spacing: 16) {
                ActivityRingsGauge(rings: rings, diameter: 66, thicknessRatio: 0.13, gapRatio: 0.05)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily rings")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(ringsSummary(rings))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        ringsDot(.inRange, "\((rings.inRangeFraction * 100).formatted(.number.precision(.fractionLength(0))))%")
                        ringsDot(.active, "\(rings.activeMinutes)m")
                        ringsDot(.sensor, "\((rings.coverageFraction * 100).formatted(.number.precision(.fractionLength(0))))%")
                    }
                    .padding(.top, 1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily rings, \(ringsSummary(rings))")
        .accessibilityHint("Opens your daily goals and source status")
    }

    private func ringsDot(_ kind: RingKind, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(kind.tint).frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
    }

    private func ringsSummary(_ rings: DailyRings) -> String {
        switch rings.metCount {
        case 3: return String(localized: "All three rings closed today")
        case 0: return String(localized: "In range · Active · Sensor")
        default: return String(localized: "\(rings.metCount) of 3 rings closed")
        }
    }

    // MARK: - Goals & streak

    /// A compact goals card: a ring for today's progress toward the target
    /// time-in-range, the current "days meeting your TIR goal" streak, and the
    /// target A1c against today's estimate. Shown only when goals are enabled.
    private func goalsCard(_ stats: PeriodStatistics, thresholds: GlucoseThresholds) -> some View {
        let goals = env.preferences.glucoseGoals
        let targetFraction = goals.targetTIRFraction
        let streak = StreakCalculator.evaluate(
            days: DailyBreakdown.perDay(readings, thresholds: thresholds),
            targetFraction: targetFraction
        )
        let todayTIR = stats.timeInRange
        let progress = targetFraction > 0 ? min(todayTIR / targetFraction, 1) : 0
        let metToday = stats.hasGlucose && todayTIR >= targetFraction
        let tirPct = (todayTIR * 100).formatted(.number.precision(.fractionLength(0)))
        let targetPct = goals.targetTIRPercent.formatted(.number.precision(.fractionLength(0)))
        let estA1c = stats.glucoseManagementIndicator

        let editButton = AnyView(
            Button {
                Haptics.play(.selection)
                showGoalsEditor = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Edit goals")
        )

        return SectionCard("Goals", systemImage: "target", accessory: editButton) {
            HStack(spacing: 18) {
                GoalProgressRing(
                    progress: progress,
                    centerText: "\(tirPct)%",
                    met: metToday
                )
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.title3)
                            .foregroundStyle(streak.current > 0 ? Theme.zoneWarning : Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(streakText(streak.current))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                            Text(streak.best > 0 ? "Best \(streak.best) · Goal \(targetPct)% TIR" : "Goal \(targetPct)% in range")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "cross.case")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                        Text(a1cText(target: goals.targetA1c, estimate: estA1c, hasGlucose: stats.hasGlucose))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(goalsAccessibilityLabel(
                tirPct: tirPct, targetPct: targetPct, streak: streak,
                target: goals.targetA1c, estimate: estA1c, hasGlucose: stats.hasGlucose
            ))
        }
    }

    private func streakText(_ current: Int) -> String {
        switch current {
        case 0: return String(localized: "Start your streak today")
        case 1: return String(localized: "1 day streak")
        default: return String(localized: "\(current) day streak")
        }
    }

    private func a1cText(target: Double, estimate: Double, hasGlucose: Bool) -> String {
        let targetStr = target.formatted(.number.precision(.fractionLength(1)))
        guard hasGlucose else { return String(localized: "A1c goal \(targetStr)%") }
        let estStr = estimate.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "A1c goal \(targetStr)% · est. \(estStr)% today")
    }

    private func goalsAccessibilityLabel(
        tirPct: String, targetPct: String, streak: StreakCalculator.StreakResult,
        target: Double, estimate: Double, hasGlucose: Bool
    ) -> String {
        var parts = ["Goals. Today \(tirPct) percent in range, target \(targetPct) percent."]
        parts.append(streak.current > 0 ? "\(streak.current) day streak, best \(streak.best)." : "No active streak.")
        parts.append(a1cText(target: target, estimate: estimate, hasGlucose: hasGlucose) + ".")
        return parts.joined(separator: " ")
    }

    // MARK: - On board (insulin + carbs)

    private func onBoardCard(iob: Double, cob: Double) -> some View {
        SectionCard("On board", systemImage: "chart.line.downtrend.xyaxis") {
            HStack(spacing: 18) {
                onBoardMetric(value: iob.formatted(.number.precision(.fractionLength(1))), unit: "U", label: String(localized: "Insulin"), tint: Theme.accent)
                Divider().frame(height: 34).overlay(Theme.hairline)
                onBoardMetric(value: cob.formatted(.number.precision(.fractionLength(0))), unit: "g", label: String(localized: "Carbs"), tint: Theme.zoneHigh)
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

    // MARK: - Sensor banner

    private func sensorBanner(session: SensorSession, status: SensorStatus) -> some View {
        NavigationLink {
            SensorView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: SensorStatusStyle.icon(status.phase))
                    .font(.title3)
                    .foregroundStyle(SensorStatusStyle.tint(status.phase))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SensorStatusStyle.title(status.phase))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(SensorStatusStyle.detail(status))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Today's checks (logging schedule)

    private var glucoseScheduleStatuses: [GlucoseSlotStatus] {
        let schedule = env.preferences.glucoseSchedule
        guard !schedule.activeSlots.isEmpty else { return [] }
        let times = readings.filter(\.isActive).map(\.timestamp)
        return GlucoseScheduleEvaluator.status(schedule: schedule, readingTimes: times, now: Date())
    }

    private func scheduleCard(_ statuses: [GlucoseSlotStatus]) -> some View {
        let progress = GlucoseScheduleEvaluator.progress(statuses)
        let badge = AnyView(
            Text("\(progress.done)/\(progress.total)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(progress.done == progress.total ? Theme.zoneInRange : Theme.textSecondary)
                .contentTransition(.numericText())
        )
        return SectionCard("Today's checks", systemImage: "checklist", accessory: badge) {
            VStack(spacing: 0) {
                ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                    scheduleRow(status)
                    if index < statuses.count - 1 {
                        Divider().overlay(Theme.hairline).padding(.leading, 38)
                    }
                }
            }
        }
    }

    private func scheduleRow(_ status: GlucoseSlotStatus) -> some View {
        Button {
            if status.state != .done {
                Haptics.play(.light)
                showGlucoseEntry = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: scheduleIcon(status.state))
                    .font(.title3)
                    .foregroundStyle(scheduleTint(status.state))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    // Look the (stored, English-default) label up in the catalog so
                    // the preset slot names localize; custom names fall through as-is.
                    Text(LocalizedStringKey(status.slot.label))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    Text(scheduleStateText(status.state))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(slotTimeText(status.slot))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(status.state == .done)
        .accessibilityElement(children: .combine)
    }

    private func scheduleIcon(_ state: GlucoseSlotState) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .due: return "exclamationmark.circle.fill"
        case .upcoming: return "clock"
        }
    }
    private func scheduleTint(_ state: GlucoseSlotState) -> Color {
        switch state {
        case .done: return Theme.zoneInRange
        case .due: return Theme.zoneWarning
        case .upcoming: return Theme.textTertiary
        }
    }
    private func scheduleStateText(_ state: GlucoseSlotState) -> LocalizedStringKey {
        switch state {
        case .done: return "Logged"
        case .due: return "Due now"
        case .upcoming: return "Upcoming"
        }
    }
    private func slotTimeText(_ slot: GlucoseLogSlot) -> String {
        var comps = DateComponents()
        comps.hour = slot.hour
        comps.minute = slot.minute
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Recent entries

    @ViewBuilder
    private func recentRow(summary: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Recent").foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent)
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                NavigationLink { InsulinLogView() } label: { insulinTile(summary.lastInsulin) }
                    .buttonStyle(PressableCardStyle())
                NavigationLink { MealLogView() } label: { mealTile(summary.lastMeal) }
                    .buttonStyle(PressableCardStyle())
                NavigationLink { ActivityLogView() } label: { activityTile(summary.lastActivity) }
                    .buttonStyle(PressableCardStyle())
            }
        }
    }

    private func insulinTile(_ dose: InsulinDose?) -> some View {
        StatTile(
            title: "Insulin",
            value: dose.map { String(localized: "\($0.units.formatted()) U") } ?? "—",
            caption: dose.map { "\(dashboardRelativeText($0.timestamp)) · \($0.insulinType.label)" } ?? String(localized: "No doses"),
            tint: Theme.accent,
            systemImage: "syringe.fill"
        )
    }

    private func mealTile(_ meal: CarbEntry?) -> some View {
        StatTile(
            title: "Meal",
            value: meal.map { String(localized: "\($0.grams.formatted()) g") } ?? "—",
            caption: meal.map { "\($0.mealType.label) · \(dashboardRelativeText($0.timestamp))" } ?? String(localized: "No meals"),
            tint: Theme.zoneHigh,
            systemImage: "fork.knife"
        )
    }

    private func activityTile(_ session: ActivityEntry?) -> some View {
        // Prefer today's Apple Health exercise time (matches the Watch's green
        // ring); fall back to the most recent logged workout, then to empty.
        let value: String
        let caption: String
        if healthActiveMinutes > 0 {
            value = String(localized: "\(healthActiveMinutes) min")
            caption = String(localized: "Exercise today")
        } else if let session {
            value = String(localized: "\(session.durationMinutes) min")
            caption = "\(session.activityType.label) · \(dashboardRelativeText(session.startTimestamp))"
        } else {
            value = "—"
            caption = String(localized: "No activity")
        }
        return StatTile(title: "Activity", value: value, caption: caption,
                        tint: Theme.zoneInRange, systemImage: "figure.walk")
    }

    /// Reads today's Apple Health exercise minutes (a single daily-bucket
    /// statistics query — cheap, off the main thread) for the Active ring + tile.
    private func refreshHealthActivity() async {
        let minutes = (await env.healthKit.dailyMetric(.exercise, days: 1)).last?.value ?? 0
        healthActiveMinutes = Int(minutes.rounded())
    }
}

/// The selectable window for the dashboard trend chart.
/// The dashboard quick-action row's five entry types, driving `.sheet(item:)`.
enum DashboardQuickAction: String, Identifiable {
    case glucose, carbs, insulin, activity, note
    var id: String { rawValue }
}

private enum DashboardTrendRange: String, CaseIterable, Identifiable {
    case threeHours, sixHours, twelveHours, twentyFourHours, custom
    var id: String { rawValue }

    /// Window length in hours (custom is handled separately).
    var hours: Double {
        switch self {
        case .threeHours: return 3
        case .sixHours: return 6
        case .twelveHours: return 12
        case .twentyFourHours: return 24
        case .custom: return 0
        }
    }

    /// The compact label shown on the picker button.
    var shortLabel: String {
        switch self {
        case .threeHours: return "3h"
        case .sixHours: return "6h"
        case .twelveHours: return "12h"
        case .twentyFourHours: return "24h"
        case .custom: return String(localized: "Custom")
        }
    }

    var menuLabel: LocalizedStringKey {
        switch self {
        case .threeHours: return "Last 3 hours"
        case .sixHours: return "Last 6 hours"
        case .twelveHours: return "Last 12 hours"
        case .twentyFourHours: return "Last 24 hours"
        case .custom: return "Custom range"
        }
    }

    var titleKey: LocalizedStringKey { menuLabel }
}

/// A non-blocking, dismissible banner shown at the top of the Dashboard when a
/// pull-to-refresh hits a genuine source/network error. Auto-dismisses; never
/// interrupts the user the way a modal alert does.
private struct SyncErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.zoneWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Couldn't refresh. \(message)")
    }
}

/// Human-friendly relative time ("5 min ago") for the dashboard's recent tiles.
/// Free function so it stays outside any actor isolation and is trivially reused.
private func dashboardRelativeText(_ date: Date, relativeTo now: Date = Date()) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
}

/// A small Apple-rings-style progress ring for the goals card. `progress` is
/// clamped to 0…1; the ring turns green and shows a check once the goal is met.
private struct GoalProgressRing: View {
    let progress: Double
    let centerText: String
    let met: Bool
    var diameter: CGFloat = 78

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(progress, 0), 1) }
    private var tint: Color { met ? Theme.zoneInRange : Theme.accent }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            Circle()
                .trim(from: 0, to: appeared ? clamped : 0)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: clamped)
            VStack(spacing: 1) {
                Text(centerText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if met {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.zoneInRange)
                }
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

/// A small editor for the opt-in Time-in-Range and A1c goals. Writes straight
/// through to `Preferences.glucoseGoals`, which persists on each change. This is
/// the reachable entry point for enabling goals, since the goals card itself is
/// hidden while they're off.
struct GoalsEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = env.preferences
        NavigationStack {
            Form {
                Section {
                    Toggle("Show goals & streak", isOn: $preferences.glucoseGoals.enabled)
                } footer: {
                    Text("Track a target time-in-range and A1c, with a streak of days that meet your TIR goal.")
                }

                Section("Time in range") {
                    Stepper(value: $preferences.glucoseGoals.targetTIRPercent, in: 40...95, step: 5) {
                        HStack {
                            Text("Target")
                            Spacer()
                            Text("\(preferences.glucoseGoals.targetTIRPercent.formatted(.number.precision(.fractionLength(0))))%")
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    Toggle("Per time-of-day targets", isOn: $preferences.periodTIRTargets.enabled)
                    if preferences.periodTIRTargets.enabled {
                        periodStepper("Overnight", $preferences.periodTIRTargets.overnightPercent)
                        periodStepper("Morning", $preferences.periodTIRTargets.morningPercent)
                        periodStepper("Afternoon", $preferences.periodTIRTargets.afternoonPercent)
                        periodStepper("Evening", $preferences.periodTIRTargets.eveningPercent)
                    }
                } header: {
                    Text("By time of day")
                } footer: {
                    Text("Set a separate time-in-range target for each part of the day — for example a gentler overnight goal. When off, your single target applies everywhere.")
                }

                Section("A1c") {
                    Stepper(value: $preferences.glucoseGoals.targetA1c, in: 5.0...9.0, step: 0.1) {
                        HStack {
                            Text("Target")
                            Spacer()
                            Text("\(preferences.glucoseGoals.targetA1c.formatted(.number.precision(.fractionLength(1))))%")
                                .foregroundStyle(Theme.accent)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func periodStepper(_ title: LocalizedStringKey, _ value: Binding<Double>) -> some View {
        Stepper(value: value, in: 40...95, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(0))))%")
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
        }
    }
}

#Preview("Goal ring") {
    HStack(spacing: 24) {
        GoalProgressRing(progress: 0.6, centerText: "42%", met: false)
        GoalProgressRing(progress: 1, centerText: "78%", met: true)
    }
    .padding()
    .background(Theme.background)
}

#Preview("Goals editor") {
    let env = AppEnvironment.preview()
    return GoalsEditorSheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}

#Preview {
    let env = AppEnvironment.preview()
    return DashboardView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
