import Foundation

/// One daily value for a wellness metric (a sum like steps, or an average like
/// resting heart rate), bucketed to the start of its day. Sendable so it crosses
/// out of the nonisolated HealthKit query without carrying a HealthKit type.
struct DailyMetric: Sendable, Identifiable {
    let day: Date          // start of day
    let value: Double
    var id: Date { day }
}

/// A single latest reading of a metric — value + when it was taken.
struct MetricReading: Sendable {
    let value: Double
    let date: Date
}

/// The latest blood-pressure reading (a correlated systolic/diastolic pair).
struct BloodPressureReading: Sendable {
    let systolic: Double
    let diastolic: Double
    let date: Date
}

/// The kinds of wellness metric the Health hub can show. Drives icons, units,
/// colours and how each is aggregated (a daily sum vs a daily average).
enum HealthMetricKind: String, CaseIterable, Identifiable, Sendable {
    case steps, activeEnergy, exercise
    case restingHeartRate, hrv, respiratoryRate, oxygen
    case bloodPressure, weight, sleep

    var id: String { rawValue }

    /// Whether the metric is a running total per day (steps) or a level that is
    /// averaged (heart rate). Sleep and blood pressure are handled specially.
    var isCumulative: Bool {
        switch self {
        case .steps, .activeEnergy, .exercise, .sleep: return true
        default: return false
        }
    }
}
