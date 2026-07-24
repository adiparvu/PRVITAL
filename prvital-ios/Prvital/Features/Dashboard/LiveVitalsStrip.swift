import SwiftUI

/// The live-vitals strip under the dashboard glucose ring — a calm, horizontally
/// scrollable row of the "how am I right now?" numbers: insulin- and
/// carbs-on-board, time since the last bolus, time until active insulin clears,
/// and time to the next CGM reading. Only cells with data appear, so the strip
/// stays quiet when there's nothing to say.
struct LiveVitalsStrip: View {
    let vitals: LiveVitals
    /// When true, icons render monochrome (the minimalist appearance setting).
    var monochrome: Bool = false

    var body: some View {
        let cells = cells
        if !cells.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cells) { VitalRow(model: $0, monochrome: monochrome) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    private var cells: [VitalCellModel] {
        var out: [VitalCellModel] = []
        if vitals.hasInsulinOnBoard {
            out.append(.init(id: "iob", icon: "syringe.fill", tint: Theme.accent,
                             value: vitals.insulinOnBoard.formatted(.number.precision(.fractionLength(1))),
                             unit: "U", label: String(localized: "Insulin")))
        }
        if vitals.hasCarbsOnBoard {
            out.append(.init(id: "cob", icon: "fork.knife", tint: Theme.zoneHigh,
                             value: vitals.carbsOnBoard.formatted(.number.precision(.fractionLength(0))),
                             unit: "g", label: String(localized: "Carbs")))
        }
        if let minutes = vitals.minutesToInsulinClear {
            out.append(.init(id: "clear", icon: "hourglass", tint: Theme.accent,
                             value: Self.duration(minutes), unit: nil,
                             label: String(localized: "Insulin ends")))
        }
        if let minutes = vitals.minutesSinceBolus {
            out.append(.init(id: "bolus", icon: "clock.arrow.circlepath", tint: Theme.textSecondary,
                             value: Self.duration(minutes), unit: nil,
                             label: String(localized: "Since bolus")))
        }
        if let minutes = vitals.minutesToNextReading {
            out.append(.init(id: "next", icon: "dot.radiowaves.left.and.right", tint: Theme.zoneInRange,
                             value: Self.duration(minutes), unit: nil,
                             label: String(localized: "Next reading")))
        }
        return out
    }

    /// Compact duration: "45 min" under 90 minutes, "2h 5m" above.
    private static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m >= 90 { return String(localized: "\(m / 60)h \(m % 60)m") }
        return String(localized: "\(m) min")
    }
}

private struct VitalCellModel: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let value: String
    let unit: String?
    let label: String
}

private struct VitalRow: View {
    let model: VitalCellModel
    var monochrome: Bool = false

    var body: some View {
        // Everything on one line: icon, value, then the label — no card.
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: model.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(monochrome ? Theme.textSecondary : model.tint)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)
            Text(model.value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            if let unit = model.unit {
                Text(unit).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            Text(model.label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentTransition(.numericText())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.label): \(model.value)\(model.unit.map { " " + $0 } ?? "")")
    }
}
