#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI
import Charts

/// Renders the glucose Live Activity on the Lock Screen and in the Dynamic
/// Island, from the `GlucoseActivityAttributes.ContentState`.
///
/// Two deliberately different treatments:
///   • **Lock Screen banner** — neutral (white/secondary), no zone wash. It sits
///     on the user's wallpaper next to the clock, so it stays calm and legible.
///   • **Dynamic Island** — zone-tinted and lightly animated: the value transitions
///     numerically, an out-of-range reading pulses, and expanding reveals a live
///     mini-chart. That's where the glucose colour and motion live.
///
/// Uses only shared snapshot fields + `Color(hex:)`; no domain layer.
struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            // Lock Screen / banner: neutral, no zone background tint.
            lockScreen(context.state)
                .padding(16)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Color(hex: state.zoneColorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if state.isOutOfRange {
                            Image(systemName: "drop.fill")
                                .font(.callout)
                                .foregroundStyle(tint)
                                .symbolEffect(.pulse, options: .repeating, isActive: true)
                        }
                        Text(state.valueText)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .contentTransition(.numericText(value: state.mgdL))
                        Text(state.unitText).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Image(systemName: state.trendSymbol)
                            .font(.title3.weight(.bold)).foregroundStyle(tint)
                        Text(state.trendLabel)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if state.recentMgdL.count >= 2 {
                            IslandSparkline(
                                values: state.recentMgdL,
                                lower: state.targetLowerMgdL,
                                upper: state.targetUpperMgdL,
                                tint: tint
                            )
                            .frame(height: 34)
                            .transition(.opacity)
                        }
                        HStack(spacing: 6) {
                            Text(state.zoneLabel).font(.caption.weight(.medium)).foregroundStyle(tint)
                            if let prediction = state.predictionText {
                                Text("·").foregroundStyle(.secondary)
                                Label(prediction, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text(state.updatedAt, style: .relative)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.mgdL)
                }
            } compactLeading: {
                Image(systemName: state.trendSymbol)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: state.isOutOfRange)
            } compactTrailing: {
                Text(state.valueText)
                    .fontWeight(.semibold).foregroundStyle(tint)
                    .contentTransition(.numericText(value: state.mgdL))
            } minimal: {
                Text(state.valueText)
                    .fontWeight(.semibold).foregroundStyle(tint)
                    .contentTransition(.numericText(value: state.mgdL))
            }
        }
    }

    /// The Lock Screen banner: neutral colours (white/secondary), no zone tint, so
    /// it reads calmly on the wallpaper. The glucose colour lives in the Dynamic
    /// Island instead.
    private func lockScreen(_ state: GlucoseActivityAttributes.ContentState) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.valueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: state.mgdL))
                    Text(state.unitText).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                HStack(spacing: 6) {
                    Text(state.zoneLabel).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    if let prediction = state.predictionText {
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        Label(prediction, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: state.trendSymbol).font(.title2.weight(.bold)).foregroundStyle(.white)
                Text(state.trendLabel).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A compact live sparkline for the expanded Dynamic Island: the recent readings
/// as a smooth line over a faint target band. Rounded, translucent, calm.
private struct IslandSparkline: View {
    let values: [Double]
    let lower: Double
    let upper: Double
    let tint: Color

    private var yDomain: ClosedRange<Double> {
        let all = values + [lower, upper]
        guard let lo = all.min(), let hi = all.max(), hi > lo else { return 40...200 }
        let pad = max((hi - lo) * 0.12, 6)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Upper target", upper))
                .foregroundStyle(.white.opacity(0.14))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            RuleMark(y: .value("Lower target", lower))
                .foregroundStyle(.white.opacity(0.14))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Reading", index),
                    y: .value("Glucose", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let last = values.indices.last {
                PointMark(
                    x: .value("Reading", last),
                    y: .value("Glucose", values[last])
                )
                .foregroundStyle(tint)
                .symbolSize(22)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .accessibilityLabel("Recent glucose trend")
    }
}
#endif
