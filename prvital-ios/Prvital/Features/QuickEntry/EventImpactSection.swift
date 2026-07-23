import SwiftUI

/// A compact "impact" readout for a logged event — the glucose just before, the
/// glucose ~2 h after (with the change), and any insulin that was already active.
/// Shown at the top of the insulin/meal editors so an entry reads as a small
/// story rather than an isolated number. Informational only — never advice.
struct EventImpactSection: View {
    let insight: EventInsight
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .accessibilityElement(children: .combine)
    }

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
