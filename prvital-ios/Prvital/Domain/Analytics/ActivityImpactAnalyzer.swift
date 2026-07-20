import Foundation

/// The glucose response to a single activity session: the baseline at the start,
/// the lowest glucose reached during and shortly after, and how far it fell.
struct ActivityImpact: Identifiable {
    let activityID: UUID
    let start: Date
    let activityType: ActivityType
    let durationMinutes: Int
    let baselineMgdL: Double
    /// Lowest glucose (mg/dL) during the session and its post-window.
    let nadirMgdL: Double
    let minutesToNadir: Int
    /// Change from baseline to nadir (mg/dL). Negative means glucose fell.
    var deltaMgdL: Double { nadirMgdL - baselineMgdL }

    var id: UUID { activityID }
}

/// An aggregate over sessions — the typical glucose change after activity.
struct ActivityImpactSummary: Equatable, Sendable {
    let count: Int
    /// Mean change (mg/dL); negative is the typical post-activity drop.
    let averageChangeMgdL: Double
}

/// Pairs activity sessions with the CGM trace to quantify their glucose impact.
/// Pure and deterministic. For each session it takes the baseline from the
/// reading nearest the start, then the nadir from readings during the session
/// and for an hour after. A session is only scored when both a baseline and a
/// post-start reading exist.
enum ActivityImpactAnalyzer {
    /// Extra minutes after the session end to keep watching for the nadir.
    static let postWindowMinutes: Double = 60
    static let baselineLookbackMinutes: Double = 20
    static let baselineForwardToleranceMinutes: Double = 5

    static func analyze(sessions: [ActivityEntry], readings: [GlucoseReading]) -> [ActivityImpact] {
        let active = readings
            .filter { $0.isActive }
            .sorted { $0.timestamp < $1.timestamp }
        guard !active.isEmpty else { return [] }

        let lookback = baselineLookbackMinutes * 60
        let forward = baselineForwardToleranceMinutes * 60
        let post = postWindowMinutes * 60

        return sessions
            .filter { $0.durationSeconds > 0 }
            .sorted { $0.startTimestamp < $1.startTimestamp }
            .compactMap { session -> ActivityImpact? in
                let start = session.startTimestamp
                let windowEnd = start.addingTimeInterval(Double(session.durationSeconds) + post)

                let baselineCandidates = active.filter {
                    $0.timestamp >= start.addingTimeInterval(-lookback) &&
                    $0.timestamp <= start.addingTimeInterval(forward)
                }
                guard let baseline = baselineCandidates.min(by: {
                    abs($0.timestamp.timeIntervalSince(start)) < abs($1.timestamp.timeIntervalSince(start))
                }) else { return nil }

                let postReadings = active.filter { $0.timestamp > start && $0.timestamp <= windowEnd }
                guard let nadir = postReadings.min(by: { $0.valueMgdL < $1.valueMgdL }) else { return nil }

                let minutesToNadir = Int((nadir.timestamp.timeIntervalSince(start) / 60).rounded())
                return ActivityImpact(
                    activityID: session.id,
                    start: start,
                    activityType: session.activityType,
                    durationMinutes: session.durationMinutes,
                    baselineMgdL: baseline.valueMgdL,
                    nadirMgdL: nadir.valueMgdL,
                    minutesToNadir: minutesToNadir
                )
            }
    }

    static func summary(_ impacts: [ActivityImpact]) -> ActivityImpactSummary? {
        guard !impacts.isEmpty else { return nil }
        let mean = impacts.reduce(0) { $0 + $1.deltaMgdL } / Double(impacts.count)
        return ActivityImpactSummary(count: impacts.count, averageChangeMgdL: mean)
    }
}
