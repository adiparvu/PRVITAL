import Foundation

/// Reconciles a real clinic HbA1c against the app's own estimate (the Glucose
/// Management Indicator) computed from the CGM trace over the roughly 90 days a
/// lab A1c reflects.
///
/// The difference — the "glycation gap" clinicians talk about — hints at whether
/// the sensor tends to read a little high or low relative to the blood test, or
/// whether the person's red cells glycate faster or slower than average. It is
/// purely informational and supportive; never a diagnosis.
struct A1cReconciliation: Equatable, Sendable {
    /// The lab-measured HbA1c (%).
    var labA1c: Double
    /// The estimated A1c (GMI) over the window the lab reflects (%).
    var estimatedA1c: Double
    /// `lab − estimate` (percentage points). Positive means the blood test ran
    /// higher than the sensor estimate.
    var gap: Double
    var alignment: Alignment
    /// Whether there was enough CGM coverage in the window to trust the estimate.
    var estimateReliable: Bool
    /// How many active readings fed the estimate.
    var readingCount: Int
    var labDate: Date

    enum Alignment: String, Sendable {
        case aligned     // within tolerance — sensor and lab agree
        case labHigher   // lab notably higher than the sensor estimate
        case labLower    // lab notably lower than the sensor estimate
    }
}

/// Pure, deterministic reconciliation of a lab A1c with the CGM-derived estimate.
enum A1cReconciler {
    /// An HbA1c reflects roughly the prior three months of glucose.
    static let windowDays = 90
    /// A `|gap|` at or below this (percentage points) counts as "aligned".
    static let tolerance = 0.3

    /// Reconciles `lab` against the readings in the ~90 days ending on the lab
    /// date. Returns `nil` when the lab value is missing or there is no CGM data
    /// in the window to compare against.
    static func reconcile(
        lab: LabResult,
        readings: [GlucoseReading],
        thresholds: GlucoseThresholds = .standard,
        calendar: Calendar = .current
    ) -> A1cReconciliation? {
        guard lab.value > 0 else { return nil }
        let end = lab.timestamp
        let start = calendar.date(byAdding: .day, value: -windowDays, to: end) ?? end
        let window = readings.filter { $0.isActive && $0.timestamp >= start && $0.timestamp <= end }
        guard !window.isEmpty else { return nil }

        let stats = StatisticsEngine.glucose(window, thresholds: thresholds)
        let estimate = stats.glucoseManagementIndicator
        let gap = lab.value - estimate

        let alignment: A1cReconciliation.Alignment
        if abs(gap) <= tolerance { alignment = .aligned }
        else if gap > 0 { alignment = .labHigher }
        else { alignment = .labLower }

        let coverage = GlucoseCoverage.coverage(
            readingCount: window.count, window: end.timeIntervalSince(start))

        return A1cReconciliation(
            labA1c: lab.value,
            estimatedA1c: estimate,
            gap: gap,
            alignment: alignment,
            estimateReliable: GlucoseCoverage.isReliable(coverage),
            readingCount: window.count,
            labDate: lab.timestamp)
    }
}
