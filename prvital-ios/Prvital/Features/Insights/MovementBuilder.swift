import Foundation
import SwiftData

/// Everything the "Movement & glucose" screen draws for one window — plain
/// Sendable values, safe to hop off the builder actor.
struct MovementPayload: Sendable {
    /// One plotted glucose point. On a Day window it is a single reading
    /// (`low == high == mgdL`); over longer windows it is a time bucket, where
    /// `mgdL` is the bucket average and `low…high` its true spread.
    struct GlucosePoint: Sendable, Identifiable {
        let id: Int
        let date: Date
        let mgdL: Double
        let low: Double
        let high: Double
    }

    /// A logged activity session, flattened out of its `@Model`.
    struct Session: Sendable, Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        let typeRaw: String
        let minutes: Int
    }

    var points: [GlucosePoint] = []
    /// True when `points` are individual readings rather than bucket averages —
    /// the chart drops the spread band and the caption changes accordingly.
    var isRaw = true
    /// Sessions shaded on the chart. Capped (see `maxBands`); the counts below
    /// always describe the whole window.
    var bands: [Session] = []
    /// The most recent sessions, for the list under the chart.
    var recentSessions: [Session] = []
    var sessionCount = 0
    var totalMinutes = 0
    var impact: ActivityImpactSummary?
    var readingCount = 0
    /// The newest reading in the window, drawn as the live "now" point.
    var latestDate: Date?
    var latestMgdL: Double?
}

/// Fetches and aggregates the movement window on a background ModelActor.
///
/// The screen used to hold two live `@Query` sets pinned to a single hard-coded
/// day, which is why it never followed the Day/Week/Month/Year selection. It
/// now takes any window — and because a Year of CGM is ~100k rows, the fetch,
/// the bucketing and the activity-impact analysis all run here, off the main
/// thread, exactly like the other Insights panes.
@ModelActor
actor MovementBuilder {
    /// Cap on plotted points. Swift Charts builds a view per mark, so keeping
    /// both series inside this budget is what makes Year scroll like Day.
    private static let maxPoints = 300
    /// Cap on shaded activity bands — a year can hold hundreds of sessions, and
    /// past this many they overlap into a solid wash anyway.
    private static let maxBands = 80
    /// How many sessions the list under the chart shows.
    private static let maxListed = 12

    /// - Parameter bucketSeconds: the width of one aggregation bucket, or 0 to
    ///   plot individual readings (a Day window).
    func build(range: ClosedRange<Date>, bucketSeconds: Double) -> MovementPayload {
        let lower = range.lowerBound
        let upper = range.upperBound

        let readings = (try? modelContext.fetch(FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive && $0.timestamp >= lower && $0.timestamp <= upper },
            sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let sessions = (try? modelContext.fetch(FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { $0.startTimestamp >= lower && $0.startTimestamp <= upper },
            sortBy: [SortDescriptor(\.startTimestamp)]))) ?? []

        var payload = MovementPayload()
        payload.readingCount = readings.count
        payload.isRaw = bucketSeconds <= 0
        payload.points = payload.isRaw
            ? Self.thin(readings)
            : Self.bucket(readings, seconds: bucketSeconds, anchor: Calendar.current.startOfDay(for: lower))
        if let last = readings.last {
            payload.latestDate = last.timestamp
            payload.latestMgdL = last.valueMgdL
        }

        let flattened = sessions.map { session in
            MovementPayload.Session(
                id: session.id,
                start: session.startTimestamp,
                end: session.endTimestamp
                    ?? session.startTimestamp.addingTimeInterval(TimeInterval(session.durationSeconds)),
                typeRaw: session.activityTypeRaw,
                minutes: session.durationMinutes)
        }
        payload.sessionCount = flattened.count
        payload.totalMinutes = flattened.reduce(0) { $0 + $1.minutes }
        payload.bands = Array(flattened.suffix(Self.maxBands))
        payload.recentSessions = Array(flattened.suffix(Self.maxListed).reversed())
        payload.impact = ActivityImpactAnalyzer.summary(
            ActivityImpactAnalyzer.analyze(sessions: sessions, readings: readings))
        return payload
    }

    /// Evenly thins a time-ordered series to at most `maxPoints`, always keeping
    /// the final reading so the line reaches "now".
    private static func thin(_ readings: [GlucoseReading]) -> [MovementPayload.GlucosePoint] {
        guard !readings.isEmpty else { return [] }
        let step = max(1.0, Double(readings.count) / Double(maxPoints))
        var points: [MovementPayload.GlucosePoint] = []
        points.reserveCapacity(min(readings.count, maxPoints) + 1)
        var cursor = 0.0
        var index = 0
        while Int(cursor) < readings.count {
            let reading = readings[Int(cursor)]
            points.append(MovementPayload.GlucosePoint(
                id: index, date: reading.timestamp, mgdL: reading.valueMgdL,
                low: reading.valueMgdL, high: reading.valueMgdL))
            index += 1
            cursor += step
        }
        if let last = readings.last, points.last?.date != last.timestamp {
            points.append(MovementPayload.GlucosePoint(
                id: index, date: last.timestamp, mgdL: last.valueMgdL,
                low: last.valueMgdL, high: last.valueMgdL))
        }
        return points
    }

    /// Folds readings into fixed time buckets — average, lowest and highest per
    /// bucket — so a month or a year reads as a trend with its spread instead of
    /// an unreadable thicket of individual readings.
    private static func bucket(
        _ readings: [GlucoseReading], seconds: Double, anchor: Date
    ) -> [MovementPayload.GlucosePoint] {
        guard seconds > 0, !readings.isEmpty else { return [] }
        var sums: [Int: (sum: Double, count: Int, low: Double, high: Double)] = [:]
        for reading in readings {
            let slot = Int(floor(reading.timestamp.timeIntervalSince(anchor) / seconds))
            let value = reading.valueMgdL
            if var existing = sums[slot] {
                existing.sum += value
                existing.count += 1
                existing.low = min(existing.low, value)
                existing.high = max(existing.high, value)
                sums[slot] = existing
            } else {
                sums[slot] = (value, 1, value, value)
            }
        }
        return sums.keys.sorted().enumerated().map { index, slot in
            let entry = sums[slot]!
            // Plot each bucket at its midpoint, so the line sits over the time
            // it actually summarises rather than leaning on its left edge.
            let start = anchor.addingTimeInterval(Double(slot) * seconds + seconds / 2)
            return MovementPayload.GlucosePoint(
                id: index, date: start, mgdL: entry.sum / Double(entry.count),
                low: entry.low, high: entry.high)
        }
    }
}
