#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

/// Renders the glucose Live Activity on the Lock Screen and in the Dynamic
/// Island, from the `GlucoseActivityAttributes.ContentState`. The whole activity
/// is tinted by the current glucose zone colour, and shows an imminent low/high
/// warning when there is one. Uses only shared snapshot fields + `Color(hex:)`.
struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            let tint = Color(hex: context.state.zoneColorHex)
            lockScreen(context.state)
                .padding(16)
                // The zone colour washes the background so the activity reads at a
                // glance — "efect cu culoarea ei".
                .activityBackgroundTint(tint.opacity(0.22))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Color(hex: state.zoneColorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(state.valueText)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                        Text(state.unitText).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: state.trendSymbol)
                        .font(.title3.weight(.bold)).foregroundStyle(tint)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 3) {
                        if let prediction = state.predictionText {
                            Label(prediction, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Text(state.zoneLabel).font(.caption).foregroundStyle(tint)
                            Spacer()
                            Text(state.updatedAt, style: .relative)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: state.trendSymbol).foregroundStyle(tint)
            } compactTrailing: {
                Text(state.valueText).fontWeight(.semibold).foregroundStyle(tint)
            } minimal: {
                Text(state.valueText).fontWeight(.semibold).foregroundStyle(tint)
            }
        }
    }

    private func lockScreen(_ state: GlucoseActivityAttributes.ContentState) -> some View {
        let tint = Color(hex: state.zoneColorHex)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.valueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(state.unitText).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 6) {
                    Text(state.zoneLabel).font(.caption.weight(.medium)).foregroundStyle(tint)
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
                Image(systemName: state.trendSymbol).font(.title2.weight(.bold)).foregroundStyle(tint)
                Text(state.trendLabel).font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
