#if canImport(ActivityKit)
import ActivityKit
import WidgetKit
import SwiftUI
import Charts

/// Renders the glucose Live Activity on the Lock Screen and in the Dynamic
/// Island, from the `GlucoseActivityAttributes.ContentState`.
///
/// One activity, many presentations — selected by `state.kind`:
///   • **Live glucose** — steady / rising / falling / out-of-range, each with its
///     own colour, glyph and headline, a live squiggle beside the value, and an
///     expanded view with the 3-hour chart, quick statistics and a quick menu.
///   • **Actions** — insulin logged, meal logged, active insulin counting down,
///     next meal counting down; each with a bar that fills on its own.
///   • **Critical alerts** — low, high, sensor reconnected, sensor battery.
///
/// Two deliberately different surfaces:
///   • **Lock Screen banner** — translucent "liquid glass" over the wallpaper,
///     with the state colour on the value and glyph only, so it stays legible.
///   • **Dynamic Island** — the same state colour, plus the motion: symbols
///     breathe and pulse, the trend arrow morphs, bars fill on their own.
///
/// Uses only shared snapshot fields + `Color(hex:)`; no domain layer runs here.
struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            // Lock Screen / banner: neutral, translucent "liquid glass" — a dark
            // tint at low opacity so the wallpaper shows through as frosted glass.
            // (Omitting the tint entirely renders an opaque black slab.)
            LockScreenBanner(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let tint = Color(hex: state.stateColorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: state, tint: tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: state, tint: tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: state, tint: tint)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.mgdL)
                }
            } compactLeading: {
                CompactLeading(state: state, tint: tint)
            } compactTrailing: {
                CompactTrailing(state: state, tint: tint)
            } minimal: {
                MinimalPresentation(state: state, tint: tint)
            }
        }
    }
}

// MARK: - Compact pill

/// The leading glyph of the compact pill. Always alive: a calm "breathe" in the
/// quiet states, an urgent repeating pulse in every alert state, and a bounce
/// each time a fresh reading lands.
private struct CompactLeading: View {
    let state: GlucoseActivityAttributes.ContentState
    let tint: Color

    private var isUrgent: Bool {
        state.kind == .alertLow || state.kind == .alertHigh
            || (state.kind == .glucose && state.glucoseState == .alert)
    }

    var body: some View {
        // Deliberately small: the compact pill should hug the sensor housing,
        // not stretch into a banner (device feedback — it sat "always big").
        Group {
            if state.kind == .insulinOnBoard {
                // Active insulin reads as a lettered badge in the design, not a glyph.
                Text("IOB")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
            } else {
                Image(systemName: state.iconName)
                    .font(.footnote)
                    .foregroundStyle(tint)
                    .symbolEffect(.breathe, options: .repeating, isActive: !isUrgent)
                    .symbolEffect(.pulse, options: .repeating, isActive: isUrgent)
                    .symbolEffect(.bounce, value: state.mgdL)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The trailing half of the compact pill: the trend arrow and value for a live
/// reading (with a live squiggle of the recent readings), or the event's short
/// value — "4U", "45g", "2:45", "20%" — for every other kind.
private struct CompactTrailing: View {
    let state: GlucoseActivityAttributes.ContentState
    let tint: Color

    /// The alert presentations show the reading itself — arrow and value, like the
    /// live pill — because the number *is* the alert.
    private var showsReading: Bool {
        state.kind == .glucose || state.kind == .alertLow || state.kind == .alertHigh
    }

    var body: some View {
        // Arrow + value, nothing else, at footnote size — the earlier version
        // (larger type plus a mini sparkline) kept the pill permanently wide.
        if showsReading {
            HStack(spacing: 2) {
                Image(systemName: state.trendSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.smooth, value: state.trendSymbol)
                Text(state.valueText)
                    .font(.footnote.weight(.semibold))
                    .contentTransition(.numericText(value: state.mgdL))
            }
            .foregroundStyle(tint)
        } else if state.kind == .ruleOf15Wait {
            WaitTimerText(state: state)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
        } else if let compact = state.eventCompactText {
            Text(compact)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
        }
        // Otherwise the pill carries the glyph alone — e.g. "sensor reconnected",
        // which has no number worth showing.
    }
}

/// The minimal (single-app) presentation: just the value, or the event's number.
private struct MinimalPresentation: View {
    let state: GlucoseActivityAttributes.ContentState
    let tint: Color

    var body: some View {
        switch state.kind {
        case .glucose, .alertLow, .alertHigh:
            Text(state.valueText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText(value: state.mgdL))
        case .ruleOf15Wait:
            WaitTimerText(state: state)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
        default:
            // An action or countdown shows its own number; a state with none
            // (a reconnected sensor) falls back to the glyph.
            if let compact = state.eventCompactText {
                Text(compact)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            } else {
                Image(systemName: state.iconName).font(.footnote).foregroundStyle(tint)
            }
        }
    }
}

// MARK: - Expanded regions

/// Expanded leading: the reading (big) for glucose, the event's headline value
/// for every other kind.
private struct ExpandedLeading: View {
    let state: GlucoseActivityAttributes.ContentState
    let tint: Color

    var body: some View {
        Group {
            if state.kind == .glucose {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.valueText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: state.mgdL))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(state.unitText).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: state.iconName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        if let title = state.eventTitle {
                            Text(title)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        if state.kind == .ruleOf15Wait {
                            WaitTimerText(state: state)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(tint)
                                .monospacedDigit()
                                .lineLimit(1)
                        } else if let detail = state.eventDetail {
                            Text(detail)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(tint)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
        .padding(.leading, 6)
    }
}

/// Expanded trailing: the morphing trend arrow and its label for glucose;
/// nothing competing for space on the event presentations.
private struct ExpandedTrailing: View {
    let state: GlucoseActivityAttributes.ContentState
    let tint: Color

    var body: some View {
        Group {
            if state.kind == .glucose {
                VStack(alignment: .trailing, spacing: 1) {
                    Image(systemName: state.trendSymbol)
                        .font(.title3.weight(.bold)).foregroundStyle(tint)
                        // The arrow morphs into its new direction when the trend
                        // changes instead of hard-cutting.
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.smooth, value: state.trendSymbol)
                    Text(state.trendLabel)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if state.kind == .ruleOf15Wait {
                WaitTimerText(state: state)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
            } else if let compact = state.eventCompactText {
                Text(compact)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 6)
    }
}

/// Expanded bottom — the long-press experience, different for each kind:
/// the 3-hour chart + quick statistics + quick menu for a live reading, the
/// self-filling bar for an action or countdown, the advice card for an alert.
private struct ExpandedBottom: View {
    let state: GlucoseActivityAttributes.ContentState
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            switch state.kind {
            case .glucose:
                glucoseBody
            case .insulinLogged, .mealLogged, .insulinOnBoard, .mealCountdown, .ruleOf15Wait:
                eventBody
            case .alertLow, .alertHigh, .sensorReconnected, .sensorBattery:
                alertBody
            }
        }
        .padding(.horizontal, 6)
    }

    // The live reading: headline, chart, statistics, quick menu.
    @ViewBuilder private var glucoseBody: some View {
        HStack(spacing: 6) {
            Text(LiveActivityHeadline.text(state))
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(state.updatedAt, style: .relative)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }

        if state.recentMgdL.count >= 2 {
            IslandSparkline(
                values: state.recentMgdL,
                lower: state.targetLowerMgdL,
                upper: state.targetUpperMgdL,
                forecast: state.forecastMgdL,
                tint: tint,
                yLabels: state.chartYLabels,
                xLabels: state.chartXLabels
            )
            .frame(height: 38)
            .transition(.opacity)
        }

        // Own line so a long localized prediction isn't clipped.
        if let prediction = state.predictionText {
            HStack(spacing: 0) {
                Label(prediction, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }

        QuickStatsRow(state: state)

        if state.iobText != nil || state.cobText != nil {
            HStack(spacing: 10) {
                if let iob = state.iobText {
                    Label(iob, systemImage: "syringe.fill")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if let cob = state.cobText {
                    Label(cob, systemImage: "fork.knife")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }

        QuickMenuRow()

        // The "sensor heartbeat": a slim bar that fills on its own toward the
        // next expected reading.
        if let next = state.nextReadingAt {
            SelfFillingBar(from: state.updatedAt, to: next, tint: tint)
        }
    }

    // A logged action or a running countdown: caption + the self-filling bar.
    @ViewBuilder private var eventBody: some View {
        if let caption = state.eventCaption {
            HStack(spacing: 0) {
                Text(caption)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        if let start = state.progressStart, let end = state.progressEnd {
            SelfFillingBar(from: start, to: end, tint: tint)
        }
    }

    // A critical alert: the glyph in a tinted tile, the headline, the advice.
    @ViewBuilder private var alertBody: some View {
        HStack(spacing: 10) {
            Image(systemName: state.iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                if let detail = state.eventDetail {
                    Text(detail)
                        .font(.callout.weight(.semibold)).foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                if let caption = state.eventCaption {
                    Text(caption)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Lock Screen banner

/// The Lock Screen banner. Same four families as the Island, laid out for the
/// full banner width: the value and glyph carry the state colour, everything
/// else stays neutral white so it reads calmly over any wallpaper.
private struct LockScreenBanner: View {
    let state: GlucoseActivityAttributes.ContentState
    private var tint: Color { Color(hex: state.stateColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state.kind {
            case .glucose:
                glucoseBody
            case .insulinLogged, .mealLogged, .insulinOnBoard, .mealCountdown, .ruleOf15Wait:
                eventBody
            case .alertLow, .alertHigh, .sensorReconnected, .sensorBattery:
                alertBody
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var glucoseBody: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(state.valueText)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: state.mgdL))
                    Text(state.unitText).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                // The value and arrow carry the state colour; the headline reads
                // calmer in white.
                Text(LiveActivityHeadline.text(state))
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            // The trend, bare: a big arrow with its word underneath and nothing
            // drawn around it (device feedback: "săgeata mai mare și fără
            // chenarul acela din jurul ei"). At 30pt it holds its own against
            // the 46pt value instead of hiding inside a chip.
            VStack(spacing: 1) {
                Image(systemName: state.trendSymbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.smooth, value: state.trendSymbol)
                Text(state.trendLabel).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        // The prediction gets its own full-width line so the (often long)
        // localized text is never truncated.
        if let prediction = state.predictionText {
            Label(prediction, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        if state.iobText != nil || state.cobText != nil {
            HStack(spacing: 12) {
                if let iob = state.iobText {
                    Label(iob, systemImage: "syringe.fill")
                        .font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                if let cob = state.cobText {
                    Label(cob, systemImage: "fork.knife")
                        .font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
            }
        }
        if let next = state.nextReadingAt {
            SelfFillingBar(from: state.updatedAt, to: next, tint: tint)
                .padding(.top, 2)
        }
    }

    @ViewBuilder private var eventBody: some View {
        HStack(spacing: 12) {
            Image(systemName: state.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if let title = state.eventTitle {
                    Text(title).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                if state.kind == .ruleOf15Wait {
                    // The countdown IS the headline — ticking live, no pushes.
                    WaitTimerText(state: state)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .lineLimit(1)
                } else if let detail = state.eventDetail {
                    Text(detail)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            if state.kind != .ruleOf15Wait, let compact = state.eventCompactText {
                Text(compact)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
        if let caption = state.eventCaption {
            Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        if let start = state.progressStart, let end = state.progressEnd {
            SelfFillingBar(from: start, to: end, tint: tint).padding(.top, 2)
        }
    }

    @ViewBuilder private var alertBody: some View {
        HStack(spacing: 12) {
            Image(systemName: state.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.16), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if let detail = state.eventDetail {
                    Text(detail)
                        .font(.headline).foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                if let caption = state.eventCaption {
                    Text(caption)
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared pieces

/// The headline sentence for a live reading — "Glucose steady", "Attention: Low".
/// Falls back to the zone label if the app didn't supply one.
private enum LiveActivityHeadline {
    static func text(_ state: GlucoseActivityAttributes.ContentState) -> String {
        state.eventTitle ?? state.zoneLabel
    }
}

/// The rule-of-15 recheck countdown, ticking by itself: `Text(timerInterval:)`
/// is driven by the system between pushes, so the Lock Screen clock stays
/// accurate for the full wait with a single activity update. Falls back to the
/// pre-formatted static clock if the window is somehow gone.
private struct WaitTimerText: View {
    let state: GlucoseActivityAttributes.ContentState

    var body: some View {
        if let start = state.progressStart, let end = state.progressEnd, end > Date() {
            Text(timerInterval: start...end, countsDown: true, showsHours: false)
        } else {
            Text(state.eventCompactText ?? "0:00")
        }
    }
}

/// A slim bar that fills on its own over a time window — the next expected CGM
/// reading, a logged action's confirmation sweep, or a countdown to zero.
/// `ProgressView(timerInterval:)` is animated by ActivityKit without a state
/// update, so it is genuinely live between data pushes.
private struct SelfFillingBar: View {
    let from: Date
    let to: Date
    let tint: Color

    var body: some View {
        // A zero or inverted window would make ProgressView unhappy; skip it.
        if to > from {
            ProgressView(timerInterval: from...to, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            // Quieter than the value it sits under — a heartbeat, not a headline.
            .tint(tint.opacity(0.8))
            .frame(height: 2.5)
            .accessibilityLabel("Time remaining")
        }
    }
}

/// The quick statistics row of the expanded view: time in range, average and
/// deviation, each rendered from a pre-formatted string.
private struct QuickStatsRow: View {
    let state: GlucoseActivityAttributes.ContentState

    var body: some View {
        if state.tirText != nil || state.averageText != nil || state.deviationText != nil {
            HStack(spacing: 0) {
                if let tir = state.tirText {
                    stat(label: String(localized: "TIR"), value: tir, tint: Color(hex: LiveActivityPresentation.stableHex))
                }
                if let average = state.averageText {
                    stat(label: String(localized: "Average"), value: average, tint: Color(hex: LiveActivityPresentation.fallingHex))
                }
                if let deviation = state.deviationText {
                    stat(label: String(localized: "Deviation"), value: deviation, tint: Color(hex: LiveActivityPresentation.carbsHex))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func stat(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The quick menu of the expanded view: log glucose, insulin or a meal, or open
/// the app. `Link` is the interaction a Live Activity supports, so each tile
/// deep-links into the quick-entry hub.
private struct QuickMenuRow: View {
    var body: some View {
        HStack(spacing: 0) {
            item(icon: "drop.fill", label: String(localized: "Glucose"), url: "prvital://log/glucose")
            item(icon: "syringe.fill", label: String(localized: "Insulin"), url: "prvital://log/insulin")
            item(icon: "fork.knife", label: String(localized: "Meal"), url: "prvital://log/meal")
            item(icon: "ellipsis", label: String(localized: "More"), url: "prvital://log")
        }
    }

    @ViewBuilder private func item(icon: String, label: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.12), in: .circle)
                    Text(label)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(label)
        }
    }
}

/// A compact live chart for the expanded Dynamic Island: the recent readings as
/// a smooth line over a faint target band, the current point glowing and
/// pulsing, and the forecast continuing as a dashed tail. Axis ticks come
/// pre-formatted from the app.
private struct IslandSparkline: View {
    let values: [Double]
    let lower: Double
    let upper: Double
    var forecast: Double? = nil
    let tint: Color
    var yLabels: [String] = []
    var xLabels: [String] = []

    private var yDomain: ClosedRange<Double> {
        var all = values + [lower, upper]
        if let forecast { all.append(forecast) }
        guard let lo = all.min(), let hi = all.max(), hi > lo else { return 40...200 }
        let pad = max((hi - lo) * 0.12, 6)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        HStack(spacing: 4) {
            chart
            if !yLabels.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(yLabels.prefix(3).enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                            .lineLimit(1)
                        if index < min(yLabels.count, 3) - 1 { Spacer(minLength: 0) }
                    }
                }
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)
            }
        }
    }

    private var chart: some View {
        VStack(spacing: 1) {
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
                        y: .value("Glucose", value),
                        series: .value("Series", "history")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                if let last = values.indices.last {
                    // A soft glow halo under the current reading, mirroring the
                    // widget and the in-app chart. The genuine *pulse* is layered
                    // on top as a chartOverlay symbolEffect below.
                    PointMark(
                        x: .value("Reading", last),
                        y: .value("Glucose", values[last])
                    )
                    .foregroundStyle(tint.opacity(0.22))
                    .symbolSize(90)
                    PointMark(
                        x: .value("Reading", last),
                        y: .value("Glucose", values[last])
                    )
                    .foregroundStyle(tint)
                    .symbolSize(22)

                    // Dashed forecast continuation one step past the last reading,
                    // in its own series so it never joins the solid history line.
                    if let forecast {
                        let next = values.count
                        LineMark(x: .value("Reading", last), y: .value("Glucose", values[last]),
                                 series: .value("Series", "forecast"))
                            .interpolationMethod(.linear)
                            .foregroundStyle(tint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        LineMark(x: .value("Reading", next), y: .value("Glucose", forecast),
                                 series: .value("Series", "forecast"))
                            .interpolationMethod(.linear)
                            .foregroundStyle(tint.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        PointMark(x: .value("Reading", next), y: .value("Glucose", forecast))
                            .foregroundStyle(tint.opacity(0.6))
                            .symbolSize(14)
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            // The live pulse: a tinted dot over the current reading that breathes
            // continuously via `.symbolEffect(.pulse)` — the same "it's alive"
            // beat as the in-app trend chart, expressed with the one animation
            // API that runs inside a Live Activity.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let last = values.indices.last,
                       let plot = proxy.plotFrame,
                       let px = proxy.position(forX: last),
                       let py = proxy.position(forY: values[last]) {
                        let frame = geo[plot]
                        Image(systemName: "circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(tint)
                            .symbolEffect(.pulse, options: .repeating, isActive: true)
                            .position(x: frame.minX + px, y: frame.minY + py)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
            )

            if !xLabels.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(xLabels.prefix(4).enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Recent glucose trend")
    }
}
#endif
