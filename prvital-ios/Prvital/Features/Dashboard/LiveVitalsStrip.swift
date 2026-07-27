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
    /// Called once when the expected next-reading instant passes without fresh
    /// data replacing the strip — the dashboard uses it to nudge a sync right
    /// when the sensor's value should be there, instead of sitting on "0 s".
    var onReadingOverdue: (() -> Void)? = nil

    var body: some View {
        let cells = cells
        if !cells.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cells) {
                    VitalRow(model: $0, monochrome: monochrome, onOverdue: onReadingOverdue)
                }
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
                             label: String(localized: "Next reading"),
                             deadline: vitals.nextReadingAt))
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
    /// When set, the value renders as a live countdown to this instant —
    /// minutes while far out, ticking seconds over the final minute.
    var deadline: Date? = nil
}

private struct VitalRow: View {
    let model: VitalCellModel
    var monochrome: Bool = false
    /// Fired once, shortly after the row's deadline passes (countdown rows only).
    var onOverdue: (() -> Void)? = nil

    var body: some View {
        // Everything on one line: icon, value, then the label — no card.
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: model.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(monochrome ? Theme.textSecondary : model.tint)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)
            if let deadline = model.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    valueText(Self.countdown(to: deadline, now: context.date))
                }
            } else {
                valueText(model.value)
            }
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
        // A few seconds after the deadline passes with no fresh data (a new
        // reading replaces the deadline and restarts this task), poke the
        // owner to sync — the "0 s but nothing updated" report.
        .task(id: model.deadline) {
            guard let deadline = model.deadline, let onOverdue else { return }
            let wait = deadline.timeIntervalSinceNow + 5
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            onOverdue()
        }
    }

    private func valueText(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
    }

    /// Same minute display as the static cells while far out; once under a
    /// minute the seconds count down live. Past the deadline the row says so
    /// honestly instead of freezing on a misleading "0 s".
    private static func countdown(to deadline: Date, now: Date) -> String {
        let secs = Int(deadline.timeIntervalSince(now).rounded())
        if secs > 60 { return String(localized: "\((secs + 59) / 60) min") }
        if secs > 0 { return String(localized: "\(secs) s") }
        return String(localized: "any moment")
    }
}
