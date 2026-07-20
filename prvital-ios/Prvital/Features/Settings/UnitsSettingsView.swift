import SwiftUI

/// Units & targets. Chooses the display unit and edits the four glucose
/// thresholds that define the target range. Every value is stored in mg/dL but
/// shown in the chosen unit; changes drive the zone colours and Time-in-Range
/// used across the whole app.
struct UnitsSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    /// A working copy of the thresholds, written back on every change.
    @State private var thresholds = GlucoseThresholds.standard
    @State private var loaded = false

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }

    private var unitBinding: Binding<GlucoseUnit> {
        Binding(
            get: { env.preferences.glucoseUnit },
            set: {
                Haptics.play(.selection)
                env.preferences.glucoseUnit = $0
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Glucose unit", selection: unitBinding) {
                    ForEach(GlucoseUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Display unit")
            } footer: {
                Text("Values are stored in mg/dL and converted for display. Switching units never changes your data.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                ZonePreviewBar(thresholds: thresholds)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                UnitsThresholdStepper(
                    title: "Very low below",
                    systemImage: "arrow.down.to.line",
                    tint: Theme.zoneCritical,
                    mgdL: $thresholds.veryLow,
                    lowerBoundMgdL: 40,
                    upperBoundMgdL: thresholds.targetLower - 5,
                    unit: unit
                )
                UnitsThresholdStepper(
                    title: "Target low",
                    systemImage: "arrow.up.to.line.compact",
                    tint: Theme.zoneWarning,
                    mgdL: $thresholds.targetLower,
                    lowerBoundMgdL: thresholds.veryLow + 5,
                    upperBoundMgdL: thresholds.targetUpper - 5,
                    unit: unit
                )
                UnitsThresholdStepper(
                    title: "Target high",
                    systemImage: "arrow.down.to.line.compact",
                    tint: Theme.zoneInRange,
                    mgdL: $thresholds.targetUpper,
                    lowerBoundMgdL: thresholds.targetLower + 5,
                    upperBoundMgdL: thresholds.high - 5,
                    unit: unit
                )
                UnitsThresholdStepper(
                    title: "Very high above",
                    systemImage: "arrow.up.to.line",
                    tint: Theme.zoneHigh,
                    mgdL: $thresholds.high,
                    lowerBoundMgdL: thresholds.targetUpper + 5,
                    upperBoundMgdL: 400,
                    unit: unit
                )
            } header: {
                Text("Target range")
            } footer: {
                Text("Readings from \(GlucoseFormatting.labeled(mgdL: thresholds.targetLower, unit: unit)) to \(GlucoseFormatting.labeled(mgdL: thresholds.targetUpper, unit: unit)) count as in range. These thresholds set the green / yellow / orange / red zones and your Time-in-Range statistics.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Button {
                    Haptics.play(.selection)
                    thresholds = .standard
                } label: {
                    Label("Reset to consensus defaults", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(Theme.accent)
                }
            } footer: {
                Text("Defaults follow the international consensus: a 70–180 mg/dL target with 54 and 250 marking severe lows and highs.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Units & targets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            thresholds = env.preferences.thresholds
            loaded = true
        }
        .onChange(of: thresholds) { _, newValue in
            guard loaded else { return }
            env.preferences.thresholds = newValue
        }
    }
}

// MARK: - Private helpers

/// A live preview of the five glucose zones as the thresholds are edited: a
/// capsule split into red / orange / green / yellow / red spans, each sized to
/// its share of a 40–400 mg/dL scale. Purely illustrative, so it's hidden from
/// VoiceOver (the steppers below carry the real values).
private struct ZonePreviewBar: View {
    let thresholds: GlucoseThresholds

    private let lo = 40.0
    private let hi = 400.0

    private var spans: [(color: Color, fraction: Double)] {
        let total = hi - lo
        func f(_ a: Double, _ b: Double) -> Double { max(0, (b - a) / total) }
        return [
            (Theme.zoneCritical, f(lo, thresholds.veryLow)),
            (Theme.zoneWarning, f(thresholds.veryLow, thresholds.targetLower)),
            (Theme.zoneInRange, f(thresholds.targetLower, thresholds.targetUpper)),
            (Theme.zoneHigh, f(thresholds.targetUpper, thresholds.high)),
            (Theme.zoneCritical, f(thresholds.high, hi)),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    span.color.frame(width: geo.size.width * span.fraction)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .animation(.smooth, value: thresholds)
        .accessibilityHidden(true)
    }
}

/// A single threshold stepper. Operates in the chosen display unit while keeping
/// the underlying mg/dL storage authoritative and clamped between its neighbours.
private struct UnitsThresholdStepper: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var mgdL: Double
    let lowerBoundMgdL: Double
    let upperBoundMgdL: Double
    let unit: GlucoseUnit

    private var step: Double { unit == .mgdL ? 1 : 0.1 }

    private var range: ClosedRange<Double> {
        let lower = unit.fromMgdL(lowerBoundMgdL)
        let upper = unit.fromMgdL(upperBoundMgdL)
        return lower <= upper ? lower...upper : lower...lower
    }

    private var displayBinding: Binding<Double> {
        Binding(
            get: { unit.fromMgdL(mgdL) },
            set: { newValue in
                let candidate = unit.toMgdL(newValue)
                mgdL = min(max(candidate, lowerBoundMgdL), upperBoundMgdL)
            }
        )
    }

    var body: some View {
        Stepper(value: displayBinding, in: range, step: step) {
            HStack {
                Label {
                    Text(title).foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
                Spacer()
                Text(GlucoseFormatting.labeled(mgdL: mgdL, unit: unit))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(GlucoseFormatting.labeled(mgdL: mgdL, unit: unit))
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { UnitsSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
