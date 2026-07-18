#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI

/// Renders the glucose Live Activity on the Lock Screen and in the Dynamic
/// Island, from the `GlucoseActivityAttributes.ContentState`. Uses only the
/// shared snapshot fields + `Color(hex:)`, no app/domain code.
struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            lockScreen(context.state)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let tint = Color(hex: context.state.zoneColorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(context.state.valueText)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                        Text(context.state.unitText).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.trendSymbol)
                        .font(.title3.weight(.bold)).foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.zoneLabel).font(.caption).foregroundStyle(tint)
                        Spacer()
                        Text(context.state.updatedAt, style: .relative)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.trendSymbol).foregroundStyle(Color(hex: context.state.zoneColorHex))
            } compactTrailing: {
                Text(context.state.valueText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: context.state.zoneColorHex))
            } minimal: {
                Text(context.state.valueText)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: context.state.zoneColorHex))
            }
        }
    }

    private func lockScreen(_ state: GlucoseActivityAttributes.ContentState) -> some View {
        let tint = Color(hex: state.zoneColorHex)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.valueText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(state.unitText).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Text(state.zoneLabel).font(.caption).foregroundStyle(tint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: state.trendSymbol).font(.title2.weight(.bold)).foregroundStyle(tint)
                Text(state.trendLabel).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
#endif
