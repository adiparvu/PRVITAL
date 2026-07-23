import SwiftUI
import SwiftData
import Charts
import Observation

/// The Health hub — an Apple-Health / Revolut-inspired overview of everything the
/// app reads from Apple Health: three activity rings up top (Move / Exercise /
/// Steps), a "what moves your glucose" panel that correlates steps / sleep / HRV
/// with daily glucose, and a grid of metric cards (heart, sleep, blood pressure,
/// weight, …), each with today's value and a 7-day sparkline. Data is loaded off
/// the main thread from `HealthKitService`; the view only renders the model.
struct HealthHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = HealthHubModel()
    @State private var showingGoals = false

    // Recent glucose, bounded, used only to correlate daily-average glucose with
    // the daily Apple Health metrics (steps / sleep / HRV).
    @Query private var glucose: [GlucoseReading]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: Date())
            ?? Date().addingTimeInterval(-35 * 86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ActivityRingsCard(rings: model.rings, streak: model.stepStreak, bestStreak: model.bestStepStreak)
                if !model.correlations.isEmpty {
                    CorrelationsSection(items: model.correlations, unit: env.preferences.glucoseUnit)
                }
                if model.cards.isEmpty && model.loaded {
                    EmptyStateView(systemImage: "heart.text.square",
                                   title: "No Health data yet",
                                   message: "Allow access when Apple Health asks, then your metrics appear. Many — resting heart rate, energy, exercise, sleep — are recorded by an Apple Watch; steps come from iPhone.")
                        .glassCard()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.cards) { card in MetricCardView(card: card) }
                    }
                }
            }
            .padding()
        }
        .prvitalScreenBackground()
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingGoals = true } label: { Image(systemName: "target") }
                    .accessibilityLabel("Daily goals")
            }
        }
        .sheet(isPresented: $showingGoals) {
            NavigationStack {
                ActivityGoalsSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingGoals = false }
                        }
                    }
            }
        }
        // Keyed on the goals so editing a target re-runs the load (rings + streak
        // update). Ask for the expanded read types too: if Apple Health was
        // connected before these were added they stay "not determined", so nothing
        // loads until we request them here — which is why iOS never re-prompted.
        .task(id: env.preferences.activityGoals) {
            try? await env.healthKit.requestAuthorization()
            await model.load(env.healthKit, glucoseDaily: Self.dailyAverageGlucose(glucose),
                             goals: env.preferences.activityGoals)
        }
        .refreshable {
            try? await env.healthKit.requestAuthorization()
            await model.load(env.healthKit, glucoseDaily: Self.dailyAverageGlucose(glucose),
                             goals: env.preferences.activityGoals)
        }
    }

    /// Collapses the recent readings into one average per calendar day — the
    /// series the correlations are computed against.
    static func dailyAverageGlucose(_ readings: [GlucoseReading]) -> [DailyMetric] {
        let calendar = Calendar.current
        var sum: [Date: Double] = [:]
        var count: [Date: Int] = [:]
        for reading in readings where reading.isActive {
            let day = calendar.startOfDay(for: reading.timestamp)
            sum[day, default: 0] += reading.valueMgdL
            count[day, default: 0] += 1
        }
        return sum.compactMap { day, total -> DailyMetric? in
            guard let n = count[day], n > 0 else { return nil }
            return DailyMetric(day: day, value: total / Double(n))
        }
        .sorted { $0.day < $1.day }
    }
}

// MARK: - Model

/// A single activity ring (fraction 0…1 of a daily goal).
struct ActivityRing: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let valueText: String
    let goalText: String
    let fraction: Double
    let color: Color
}

/// A metric card: title, big value, unit, a 7-day sparkline and a tint.
struct MetricCard: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let systemImage: String
    let value: String
    let unit: String
    let caption: String
    let color: Color
    let series: [DailyMetric]
    /// The Apple Health metric this card represents, so tapping opens its detail.
    let kind: HealthMetricKind?
    /// Sparkline baseline: bars for cumulative metrics, a line for levels.
    let cumulative: Bool
}

@MainActor
@Observable
final class HealthHubModel {
    var rings: [ActivityRing] = []
    var cards: [MetricCard] = []
    var correlations: [HealthGlucoseCorrelation] = []
    /// Current run of consecutive days that hit the step goal (Apple-rings style),
    /// and the best such run over the last month.
    var stepStreak = 0
    var bestStepStreak = 0
    var loaded = false

    func load(_ hk: HealthKitService, glucoseDaily: [DailyMetric], goals: ActivityGoals) async {
        let stepGoal = Double(goals.stepGoal)
        let moveGoal = Double(goals.moveGoalKcal)
        let exerciseGoal = Double(goals.exerciseMinutesGoal)
        async let stepsD = hk.dailyMetric(.steps, days: 7)
        async let energyD = hk.dailyMetric(.activeEnergy, days: 7)
        async let exerciseD = hk.dailyMetric(.exercise, days: 7)
        async let restingHRD = hk.dailyMetric(.restingHeartRate, days: 7)
        async let hrvD = hk.dailyMetric(.hrv, days: 7)
        async let respD = hk.dailyMetric(.respiratoryRate, days: 7)
        async let oxygenD = hk.dailyMetric(.oxygen, days: 7)
        async let weightD = hk.dailyMetric(.weight, days: 30)
        async let sleepD = hk.sleepHoursByNight(days: 7)
        async let bp = hk.latestBloodPressure()
        // 30-day series feed the "what moves your glucose" correlations.
        async let stepsCorrD = hk.dailyMetric(.steps, days: 30)
        async let hrvCorrD = hk.dailyMetric(.hrv, days: 30)
        async let sleepCorrD = hk.sleepHoursByNight(days: 30)

        let steps = await stepsD, energy = await energyD, exercise = await exerciseD
        let restingHR = await restingHRD, hrv = await hrvD, resp = await respD
        let oxygen = await oxygenD, weight = await weightD, sleep = await sleepD
        let pressure = await bp

        let stepsToday = steps.last?.value ?? 0
        let moveToday = energy.last?.value ?? 0
        let exToday = exercise.last?.value ?? 0

        rings = [
            ActivityRing(title: "Move", valueText: Self.int(moveToday),
                         goalText: "\(Self.int(moveGoal)) kcal",
                         fraction: min(moveToday / moveGoal, 1), color: Theme.zoneCritical),
            ActivityRing(title: "Exercise", valueText: Self.int(exToday),
                         goalText: "\(Self.int(exerciseGoal)) min",
                         fraction: min(exToday / exerciseGoal, 1), color: Theme.zoneInRange),
            ActivityRing(title: "Steps", valueText: Self.int(stepsToday),
                         goalText: Self.int(stepGoal),
                         fraction: min(stepsToday / stepGoal, 1), color: Theme.accent)
        ]

        var cards: [MetricCard] = []
        func add(_ title: LocalizedStringKey, _ image: String, _ value: String, _ unit: String,
                 _ caption: String, _ color: Color, _ series: [DailyMetric],
                 kind: HealthMetricKind, cumulative: Bool) {
            guard !value.isEmpty else { return }
            cards.append(MetricCard(title: title, systemImage: image, value: value, unit: unit,
                                    caption: caption, color: color, series: series,
                                    kind: kind, cumulative: cumulative))
        }

        add("Steps", "figure.walk", stepsToday > 0 ? Self.int(stepsToday) : "",
            String(localized: "steps"), Self.avgCaption(steps, "%@ avg"), Theme.accent, steps,
            kind: .steps, cumulative: true)
        add("Move", "flame.fill", moveToday > 0 ? Self.int(moveToday) : "",
            "kcal", Self.avgCaption(energy, "%@ avg"), Theme.zoneCritical, energy,
            kind: .activeEnergy, cumulative: true)
        add("Sleep", "bed.double.fill", sleep.last.map { Self.oneDecimal($0.value) } ?? "",
            String(localized: "h"), Self.avgCaption(sleep, "%@ h avg"), Color(hex: 0x8E7CFF), sleep,
            kind: .sleep, cumulative: true)
        add("Resting heart rate", "heart.fill", restingHR.last.map { Self.int($0.value) } ?? "",
            "bpm", Self.avgCaption(restingHR, "%@ avg"), Theme.zoneWarning, restingHR,
            kind: .restingHeartRate, cumulative: false)
        add("Heart rate variability", "waveform.path.ecg", hrv.last.map { Self.int($0.value) } ?? "",
            "ms", Self.avgCaption(hrv, "%@ avg"), Theme.accent, hrv,
            kind: .hrv, cumulative: false)
        add("Respiratory rate", "lungs.fill", resp.last.map { Self.oneDecimal($0.value) } ?? "",
            String(localized: "br/min"), "", Theme.zoneInRange, resp,
            kind: .respiratoryRate, cumulative: false)
        add("Blood oxygen", "drop.fill", oxygen.last.map { Self.int($0.value * 100) } ?? "",
            "%", "", Theme.accent, oxygen.map { DailyMetric(day: $0.day, value: $0.value * 100) },
            kind: .oxygen, cumulative: false)
        if let p = pressure {
            add("Blood pressure", "heart.circle.fill", "\(Self.int(p.systolic))/\(Self.int(p.diastolic))",
                "mmHg", Self.relative(p.date), Theme.zoneCritical, [],
                kind: .bloodPressure, cumulative: false)
        }
        add("Weight", "scalemass.fill", weight.last.map { Self.oneDecimal($0.value) } ?? "",
            "kg", "", Theme.textSecondary, weight,
            kind: .weight, cumulative: false)

        self.cards = cards

        // Correlate each daily Apple Health series with daily-average glucose, and
        // keep only the associations with enough days and a real signal.
        let stepsMonth = await stepsCorrD, hrvMonth = await hrvCorrD, sleepMonth = await sleepCorrD
        var found: [HealthGlucoseCorrelation] = []
        for candidate in [
            HealthGlucoseCorrelator.correlate(kind: .steps, health: stepsMonth, glucose: glucoseDaily),
            HealthGlucoseCorrelator.correlate(kind: .sleep, health: sleepMonth, glucose: glucoseDaily),
            HealthGlucoseCorrelator.correlate(kind: .hrv, health: hrvMonth, glucose: glucoseDaily),
        ] {
            if let c = candidate, c.isMeaningful { found.append(c) }
        }
        self.correlations = found

        // Step-goal streak from the 30-day step series (reuses the correlation fetch).
        let streak = StreakCalculator.evaluate(
            dailyValues: stepsMonth.map { (day: $0.day, value: $0.value) },
            goal: Double(goals.stepGoal))
        self.stepStreak = streak.current
        self.bestStepStreak = streak.best

        self.loaded = true
    }

    private static func int(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
    private static func oneDecimal(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
    private static func avgCaption(_ series: [DailyMetric], _ format: String) -> String {
        guard !series.isEmpty else { return "" }
        let avg = series.map(\.value).reduce(0, +) / Double(series.count)
        return String(format: NSLocalizedString(format, comment: ""), int(avg))
    }
}

// MARK: - Activity rings

private struct ActivityRingsCard: View {
    let rings: [ActivityRing]
    var streak: Int = 0
    var bestStreak: Int = 0

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Activity", systemImage: "flame.fill")
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Today").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 20) {
                TripleRing(rings: rings).frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rings) { ring in
                        HStack(spacing: 8) {
                            Circle().fill(ring.color).frame(width: 9, height: 9)
                            Text(ring.title).font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(ring.valueText).font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary).monospacedDigit()
                            Text("/ \(ring.goalText)").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            if streak > 0 {
                Divider().overlay(Theme.hairline)
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.subheadline).foregroundStyle(.orange)
                    Text(streakText).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if bestStreak > streak {
                        Text(bestText).font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var streakText: String {
        String(format: NSLocalizedString("%@-day step streak", comment: ""), "\(streak)")
    }
    private var bestText: String {
        String(format: NSLocalizedString("Best: %@ days", comment: ""), "\(bestStreak)")
    }
}

/// Three concentric Apple-style progress rings.
private struct TripleRing: View {
    let rings: [ActivityRing]
    @State private var appeared = false

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * 18
                Circle().stroke(ring.color.opacity(0.18), lineWidth: 12).padding(inset)
                Circle()
                    .trim(from: 0, to: appeared ? max(0.001, ring.fraction) : 0)
                    .stroke(ring.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { appeared = true } }
    }
}

// MARK: - Metric card

private struct MetricCardView: View {
    let card: MetricCard

    var body: some View {
        if let kind = card.kind, kind.hasDetail {
            NavigationLink {
                MetricDetailView(kind: kind, title: card.title, systemImage: card.systemImage,
                                 unit: card.unit, color: card.color, cumulative: card.cumulative)
            } label: {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: card.systemImage).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(card.color)
                Text(card.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(card.value).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(card.unit).font(.caption).foregroundStyle(Theme.textTertiary)
            }
            sparkline.frame(height: 30)
            if !card.caption.isEmpty {
                Text(card.caption).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(GlassListRowBackground().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private var sparkline: some View {
        if card.series.count > 1 {
            Chart(card.series) { point in
                if card.cumulative {
                    BarMark(x: .value("Day", point.day, unit: .day),
                            y: .value("Value", point.value))
                        .foregroundStyle(card.color.opacity(0.55))
                        .cornerRadius(2)
                } else {
                    LineMark(x: .value("Day", point.day, unit: .day),
                             y: .value("Value", point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(card.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: card.cumulative))
        } else {
            Color.clear
        }
    }
}

// MARK: - "What moves your glucose" correlations

private struct CorrelationsSection: View {
    let items: [HealthGlucoseCorrelation]
    let unit: GlucoseUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What moves your glucose", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            ForEach(items) { CorrelationCardView(correlation: $0, unit: unit) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One association: a plain sentence, a strength bar, and how many days back it.
/// Green when the metric and lower glucose move together, amber otherwise.
private struct CorrelationCardView: View {
    let correlation: HealthGlucoseCorrelation
    let unit: GlucoseUnit

    var body: some View {
        let tint = correlation.favourable ? Theme.zoneInRange : Theme.zoneHigh
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(sentence)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let deltaLine {
                Text(deltaLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(tint)
                        .frame(width: max(6, geo.size.width * min(abs(correlation.coefficient), 1)))
                }
            }
            .frame(height: 6)
            Text(caption).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassListRowBackground().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var icon: String {
        switch correlation.kind {
        case .steps: return "figure.walk"
        case .sleep: return "bed.double.fill"
        case .hrv:   return "waveform.path.ecg"
        }
    }

    private var title: LocalizedStringKey {
        switch correlation.kind {
        case .steps: return "Steps"
        case .sleep: return "Sleep"
        case .hrv:   return "Heart rate variability"
        }
    }

    private var sentence: LocalizedStringKey {
        switch (correlation.kind, correlation.favourable) {
        case (.steps, true):  return "On more active days, your glucose tends to run lower."
        case (.steps, false): return "On more active days, your glucose tends to run higher."
        case (.sleep, true):  return "After more sleep, your glucose tends to run lower."
        case (.sleep, false): return "After more sleep, your glucose tends to run higher."
        case (.hrv, true):    return "When your HRV is higher, your glucose tends to run lower."
        case (.hrv, false):   return "When your HRV is higher, your glucose tends to run higher."
        }
    }

    /// The concrete effect size, shown only when it's big enough to matter (≥ 5
    /// mg/dL). Formatted in the user's glucose unit.
    private var deltaLine: String? {
        guard abs(correlation.deltaMgdL) >= 5 else { return nil }
        let amount = GlucoseFormatting.labeled(mgdL: abs(correlation.deltaMgdL), unit: unit)
        return String(format: NSLocalizedString(
            "Glucose differs by about %@ between your highest and lowest days.", comment: ""), amount)
    }

    private var caption: String {
        String(format: NSLocalizedString("Based on %@ days — a pattern, not proof of cause.", comment: ""),
               "\(correlation.sampleSize)")
    }
}

// MARK: - Daily goals editor

/// Edits the three activity-ring targets (steps, move energy, exercise minutes).
/// Writing a stepper persists via `Preferences`, and the hub's `.task(id:)`
/// reloads so the rings and streak update immediately.
private struct ActivityGoalsSheet: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var preferences = env.preferences
        Form {
            Section {
                Stepper(value: $preferences.activityGoals.stepGoal, in: 1_000...30_000, step: 500) {
                    goalRow("Steps", "figure.walk",
                            "\(preferences.activityGoals.stepGoal.formatted()) \(String(localized: "steps"))")
                }
                Stepper(value: $preferences.activityGoals.moveGoalKcal, in: 50...2_000, step: 50) {
                    goalRow("Move", "flame.fill", "\(preferences.activityGoals.moveGoalKcal) kcal")
                }
                Stepper(value: $preferences.activityGoals.exerciseMinutesGoal, in: 5...240, step: 5) {
                    goalRow("Exercise", "figure.run",
                            "\(preferences.activityGoals.exerciseMinutesGoal) \(String(localized: "min"))")
                }
            } header: {
                Text("Daily goals")
            } footer: {
                Text("Your activity rings and step streak use these targets.")
            }
        }
        .navigationTitle("Daily goals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func goalRow(_ title: LocalizedStringKey, _ icon: String, _ value: String) -> some View {
        HStack {
            Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(Theme.accent) }
            Spacer()
            Text(value).foregroundStyle(Theme.accent).monospacedDigit()
        }
    }
}
