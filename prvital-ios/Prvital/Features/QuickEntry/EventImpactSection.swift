import SwiftUI
import Charts

/// The "impact" readout for a logged event — the glucose just before, the
/// glucose a chosen 2–5 h later (with the change), the insulin that was already
/// active, and the actual curve in between. Shown at the top of the
/// insulin/meal editors so an entry reads as a small story rather than an
/// isolated number. Informational only — never advice.
struct EventImpactSection: View {
    let eventDate: Date
    let readings: [GlucoseReading]
    let insulin: [InsulinDose]
    let excludingDoseID: UUID?
    let bolus: BolusParameters
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds

    /// The after-window in hours (2–5), seeded from the app's postprandial
    /// setting and adjustable right here — a slow meal tells its story at 4–5 h,
    /// a correction at 2.
    @State private var windowHours: Int

    init(eventDate: Date, readings: [GlucoseReading], insulin: [InsulinDose],
         excludingDoseID: UUID?, bolus: BolusParameters,
         unit: GlucoseUnit, thresholds: GlucoseThresholds,
         initialWindowHours: Int = 3) {
        self.eventDate = eventDate
        self.readings = readings
        self.insulin = insulin
        self.excludingDoseID = excludingDoseID
        self.bolus = bolus
        self.unit = unit
        self.thresholds = thresholds
        _windowHours = State(initialValue: min(5, max(2, initialWindowHours)))
    }

    private var insight: EventInsight {
        EventInsight.make(
            eventDate: eventDate, excludingDoseID: excludingDoseID,
            readings: readings, insulin: insulin, bolus: bolus,
            afterHours: Double(windowHours))
    }

    private var chartStart: Date { eventDate.addingTimeInterval(-30 * 60) }
    private var chartEnd: Date { eventDate.addingTimeInterval(Double(windowHours) * 3600) }

    private var windowReadings: [GlucoseReading] {
        readings
            .filter { $0.isActive && $0.timestamp >= chartStart && $0.timestamp <= chartEnd }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        let insight = insight
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $windowHours) {
                ForEach([2, 3, 4, 5], id: \.self) { hours in
                    Text(verbatim: "\(hours) h").tag(hours)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 14) {
                glucoseColumn(title: "Before", mgdL: insight.glucoseBefore)
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
                glucoseColumn(title: "After", mgdL: insight.glucoseAfter)
                Spacer()
                if let delta = insight.deltaMgdL {
                    deltaBadge(delta)
                } else if insight.glucoseBefore != nil {
                    Text("Still developing")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if windowReadings.count >= 2 {
                responseChart
            }

            if let iob = insight.iobBefore, iob >= 0.05 {
                HStack(spacing: 6) {
                    Image(systemName: "syringe.fill")
                        .font(.caption2).foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Insulin on board").font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(iob.formatted(.number.precision(.fractionLength(1)))) U")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: windowHours)
    }

    // MARK: Chart

    /// The glucose curve from half an hour before the event through the chosen
    /// window: target band underneath, a dashed rule at the event moment, and
    /// the readings as one line. The x-domain always spans the full window, so
    /// a story still developing shows its empty room to the right.
    private var responseChart: some View {
        Chart {
            RectangleMark(
                xStart: .value("Start", chartStart), xEnd: .value("End", chartEnd),
                yStart: .value("Low", unit.fromMgdL(thresholds.targetLower)),
                yEnd: .value("High", unit.fromMgdL(thresholds.targetUpper)))
                .foregroundStyle(Theme.zoneInRange.opacity(0.10))
            ForEach(windowReadings) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", unit.fromMgdL(reading.valueMgdL)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            RuleMark(x: .value("Event", eventDate))
                .foregroundStyle(Theme.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartXScale(domain: chartStart...chartEnd)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 130)
        .accessibilityLabel(Text("Glucose response chart"))
    }

    private var yDomain: ClosedRange<Double> {
        let bandLow = unit.fromMgdL(thresholds.targetLower)
        let bandHigh = unit.fromMgdL(thresholds.targetUpper)
        let values = windowReadings.map { unit.fromMgdL($0.valueMgdL) }
        let low = min(values.min() ?? bandLow, bandLow)
        let high = max(values.max() ?? bandHigh, bandHigh)
        let pad = (high - low) * 0.12 + (unit == .mgdL ? 5 : 0.3)
        return (low - pad)...(high + pad)
    }

    // MARK: Figures

    private func glucoseColumn(title: LocalizedStringKey, mgdL: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.textTertiary)
            if let mgdL {
                Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(thresholds.zone(forMgdL: mgdL).color)
                    .monospacedDigit()
            } else {
                Text(verbatim: "—").font(.headline).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let up = delta >= 0
        let text = (up ? "+" : "−") + GlucoseFormatting.string(mgdL: abs(delta), unit: unit)
        return Text(verbatim: text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(up ? Theme.zoneHigh : Theme.zoneInRange)
            .monospacedDigit()
    }
}
