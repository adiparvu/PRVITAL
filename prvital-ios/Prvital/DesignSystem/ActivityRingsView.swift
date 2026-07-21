import SwiftUI

/// Identity for one of the three daily rings — its colour, icon and label. Keeps
/// the gauge and the legend rows visually in sync from a single definition.
enum RingKind: CaseIterable, Identifiable {
    case inRange
    case active
    case sensor

    var id: Self { self }

    var tint: Color {
        switch self {
        case .inRange: return Theme.zoneInRange
        case .active: return Theme.zoneWarning
        case .sensor: return Theme.accent
        }
    }

    var symbol: String {
        switch self {
        case .inRange: return "target"
        case .active: return "figure.walk.motion"
        case .sensor: return "dot.radiowaves.left.and.right"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .inRange: return "In range"
        case .active: return "Active"
        case .sensor: return "Sensor"
        }
    }

    /// The same title as a resolved `String`, for composing accessibility labels.
    var accessibilityTitle: String {
        switch self {
        case .inRange: return String(localized: "In range")
        case .active: return String(localized: "Active")
        case .sensor: return String(localized: "Sensor")
        }
    }
}

/// Three concentric progress rings — In range (outer), Active (middle), Sensor
/// (inner) — in the spirit of Apple's activity rings but tuned for diabetes.
/// Purely presentational: it takes the already-computed `DailyRings` and animates
/// each ring's trim on appear. Hidden from VoiceOver; callers pair it with a
/// labelled legend that carries the real values.
struct ActivityRingsGauge: View {
    let rings: DailyRings
    var diameter: CGFloat = 168
    /// Ring thickness as a fraction of the diameter.
    var thicknessRatio: CGFloat = 0.11
    /// Gap between rings as a fraction of the diameter.
    var gapRatio: CGFloat = 0.045

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { diameter * thicknessRatio }
    private var gap: CGFloat { diameter * gapRatio }

    /// Outer → inner, each with its diameter.
    private var ringLayers: [(kind: RingKind, progress: Double, size: CGFloat)] {
        let inset = lineWidth + gap
        return [
            (.inRange, rings.inRangeProgress, diameter),
            (.active, rings.activeProgress, diameter - inset * 2),
            (.sensor, rings.coverageProgress, diameter - inset * 4),
        ]
    }

    var body: some View {
        ZStack {
            ForEach(ringLayers, id: \.kind) { layer in
                ringView(tint: layer.kind.tint, progress: layer.progress)
                    .frame(width: layer.size, height: layer.size)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { appeared = true } }
        }
        .accessibilityHidden(true)
    }

    private func ringView(tint: Color, progress: Double) -> some View {
        let clamped = min(max(progress, 0), 1)
        return ZStack {
            Circle()
                .stroke(tint.opacity(0.16), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: appeared ? clamped : 0)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: clamped)
        }
    }
}

#Preview {
    ActivityRingsGauge(
        rings: DailyRings(
            inRangeFraction: 0.72, inRangeGoalFraction: 0.70,
            activeMinutes: 18, activeGoalMinutes: 30,
            coverageFraction: 0.93, coverageGoalFraction: 0.85,
            hasGlucose: true
        )
    )
    .padding(40)
    .background(Theme.background)
}
