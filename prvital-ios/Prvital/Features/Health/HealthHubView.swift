import SwiftUI
import Charts
import Observation

/// The Health hub — an Apple-Health / Revolut-inspired overview of everything the
/// app reads from Apple Health: three activity rings up top (Move / Exercise /
/// Steps) and a grid of metric cards (heart, sleep, blood pressure, weight, …),
/// each with today's value and a 7-day sparkline. Data is loaded off the main
/// thread from `HealthKitService`; the view only renders the prepared model.
struct HealthHubView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = HealthHubModel()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ActivityRingsCard(rings: model.rings)
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
        .task {
            // Ask for the expanded read types (steps, sleep, HRV, energy, …). If
            // Apple Health was connected before these were added, they're still
            // "not determined", so nothing loads until we request them here — which
            // is why iOS never re-prompted. This triggers the sheet for the new
            // types, then loads.
            try? await env.healthKit.requestAuthorization()
            await model.load(env.healthKit)
        }
        .refreshable {
            try? await env.healthKit.requestAuthorization()
            await model.load(env.healthKit)
        }
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
    /// Sparkline baseline: bars for cumulative metrics, a line for levels.
    let cumulative: Bool
}

@MainActor
@Observable
final class HealthHubModel {
    var rings: [ActivityRing] = []
    var cards: [MetricCard] = []
    var loaded = false

    // Daily goals (sensible defaults; personalisation comes later).
    private let stepGoal = 10_000.0
    private let moveGoal = 500.0      // kcal active energy
    private let exerciseGoal = 30.0   // minutes

    func load(_ hk: HealthKitService) async {
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
                 _ caption: String, _ color: Color, _ series: [DailyMetric], cumulative: Bool) {
            guard !value.isEmpty else { return }
            cards.append(MetricCard(title: title, systemImage: image, value: value, unit: unit,
                                    caption: caption, color: color, series: series, cumulative: cumulative))
        }

        add("Steps", "figure.walk", stepsToday > 0 ? Self.int(stepsToday) : "",
            String(localized: "steps"), Self.avgCaption(steps, "%@ avg"), Theme.accent, steps, cumulative: true)
        add("Move", "flame.fill", moveToday > 0 ? Self.int(moveToday) : "",
            "kcal", Self.avgCaption(energy, "%@ avg"), Theme.zoneCritical, energy, cumulative: true)
        add("Sleep", "bed.double.fill", sleep.last.map { Self.oneDecimal($0.value) } ?? "",
            String(localized: "h"), Self.avgCaption(sleep, "%@ h avg"), Color(hex: 0x8E7CFF), sleep, cumulative: true)
        add("Resting heart rate", "heart.fill", restingHR.last.map { Self.int($0.value) } ?? "",
            "bpm", Self.avgCaption(restingHR, "%@ avg"), Theme.zoneWarning, restingHR, cumulative: false)
        add("Heart rate variability", "waveform.path.ecg", hrv.last.map { Self.int($0.value) } ?? "",
            "ms", Self.avgCaption(hrv, "%@ avg"), Theme.accent, hrv, cumulative: false)
        add("Respiratory rate", "lungs.fill", resp.last.map { Self.oneDecimal($0.value) } ?? "",
            String(localized: "br/min"), "", Theme.zoneInRange, resp, cumulative: false)
        add("Blood oxygen", "drop.fill", oxygen.last.map { Self.int($0.value * 100) } ?? "",
            "%", "", Theme.accent, oxygen.map { DailyMetric(day: $0.day, value: $0.value * 100) }, cumulative: false)
        if let p = pressure {
            add("Blood pressure", "heart.circle.fill", "\(Self.int(p.systolic))/\(Self.int(p.diastolic))",
                "mmHg", Self.relative(p.date), Theme.zoneCritical, [], cumulative: false)
        }
        add("Weight", "scalemass.fill", weight.last.map { Self.oneDecimal($0.value) } ?? "",
            "kg", "", Theme.textSecondary, weight, cumulative: false)

        self.cards = cards
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
