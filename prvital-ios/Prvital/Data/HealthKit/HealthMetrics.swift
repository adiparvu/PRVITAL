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

    /// Blood pressure has no single series, so it gets no detail screen.
    var hasDetail: Bool { self != .bloodPressure }
}

/// The window a metric-detail screen shows, mirroring Apple Health: a day of
/// hourly buckets, a week/month of daily buckets, or a year of monthly buckets.
enum MetricInterval: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    var id: String { rawValue }
}

/// A bucketed series for one metric over one interval, plus the summary figures
/// the detail screen shows (average / lowest / highest). Values are already in
/// the metric's display unit.
struct MetricSeries: Sendable {
    let points: [DailyMetric]
    let average: Double
    let minimum: Double
    let maximum: Double

    var isEmpty: Bool { points.isEmpty }
    static let empty = MetricSeries(points: [], average: 0, minimum: 0, maximum: 0)
}
