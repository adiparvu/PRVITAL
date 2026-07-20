import Foundation

/// Builds the read-only **care summary** a person shares with a partner,
/// caregiver or clinician — a plain, private snapshot of how their glucose has
/// been, plus who they are. Pure and testable: it takes already-computed
/// statistics and returns text, so no store or UI is involved.
enum CareSummaryComposer {
    struct Input: Sendable {
        var name: String
        var diabetesType: String
        var therapy: String
        var periodLabel: String
        var unit: GlucoseUnit
        var stats: PeriodStatistics
        var generatedAt: Date
    }

    /// A shareable, human-readable summary (plain text that also reads cleanly as
    /// Markdown in Messages/Mail).
    static func text(_ input: Input) -> String {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = name.isEmpty ? "Prvital user" : name
        var lines: [String] = []
        lines.append("Prvital care summary")
        lines.append("\(who) — \(input.diabetesType) · \(input.therapy)")
        lines.append("\(input.periodLabel) · generated \(dateString(input.generatedAt))")
        lines.append("")

        let s = input.stats
        if s.readingCount == 0 {
            lines.append("No glucose readings in this period.")
        } else {
            lines.append("Glucose")
            lines.append("• Time in range: \(percent(s.timeInRange))")
            lines.append("• Average: \(GlucoseFormatting.labeled(mgdL: s.average, unit: input.unit))")
            lines.append("• Est. A1c (GMI): \(oneDecimal(s.glucoseManagementIndicator))%")
            lines.append("• Below range: \(percent(s.timeBelowRange)) (very low: \(percent(s.timeVeryLow)))")
            lines.append("• Above range: \(percent(s.timeAboveRange)) (very high: \(percent(s.timeVeryHigh)))")
            lines.append("• Variability (CV): \(percent(s.coefficientOfVariation))")
            lines.append("• Low events: \(s.hypoEvents) · High events: \(s.hyperEvents)")
            lines.append("• Readings: \(s.readingCount)")
        }

        lines.append("")
        lines.append("Shared from Prvital. This contains sensitive health data — please keep it private.")
        return lines.joined(separator: "\n")
    }

    /// A 0...1 fraction as a whole-number percentage, e.g. 0.723 → "72%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
