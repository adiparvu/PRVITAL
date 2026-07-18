import SwiftUI
import Charts

/// The dashboard hero: a circular gauge showing the current glucose value,
/// tinted by its zone, with the trend arrow beneath.
struct GlucoseGaugeRing: View {
    let mgdL: Double
    let zone: GlucoseZone
    let unit: GlucoseUnit
    var trend: GlucoseTrend?
    var diameter: CGFloat = 200

    /// Display scale for the ring sweep (clamped).
    private let scaleLow = 40.0
    private let scaleHigh = 320.0

    private var fraction: Double {
        min(max((mgdL - scaleLow) / (scaleHigh - scaleLow), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(zone.color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: fraction)
            VStack(spacing: 2) {
                Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit.rawValue).font(.subheadline).foregroundStyle(Theme.textSecondary)
                if let trend {
                    TrendBadge(trend: trend, showsLabel: true).padding(.top, 2)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Glucose \(GlucoseFormatting.labeled(mgdL: mgdL, unit: unit)), \(zone.label)"
                            + (trend.map { ", \($0.label)" } ?? ""))
    }
}

/// A line chart of glucose over time with the target range shaded, built on
/// Swift Charts. Values are plotted in mg/dL and the axis is formatted to the
/// display unit.
struct GlucoseTrendChart: View {
    let readings: [GlucoseReading]
    let thresholds: GlucoseThresholds
    let unit: GlucoseUnit
    var compact = false

    private var sorted: [GlucoseReading] {
        readings.filter(\.isActive).sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Target upper", thresholds.targetUpper))
                .foregroundStyle(Theme.zoneInRange.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            RuleMark(y: .value("Target lower", thresholds.targetLower))
                .foregroundStyle(Theme.zoneInRange.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(sorted) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("Glucose", reading.valueMgdL)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.accent)

                if !compact {
                    PointMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Glucose", reading.valueMgdL)
                    )
                    .symbolSize(18)
                    .foregroundStyle(thresholds.zone(forMgdL: reading.valueMgdL).color)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 3 : 5)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let mgdL = value.as(Double.self) {
                        Text(GlucoseFormatting.string(mgdL: mgdL, unit: unit))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.5))
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .frame(height: compact ? 120 : 220)
    }

    private var yDomain: ClosedRange<Double> {
        let values = sorted.map(\.valueMgdL)
        let low = min(values.min() ?? thresholds.targetLower, thresholds.targetLower) - 20
        let high = max(values.max() ?? thresholds.targetUpper, thresholds.targetUpper) + 20
        return max(0, low)...high
    }
}
