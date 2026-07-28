import Foundation

/// MARD-style agreement between the user's own meter checks and their sensor.
struct SensorAccuracyResult: Sendable {
    /// Number of reference ↔ sensor pairs the figures below are computed from.
    let pairCount: Int
    /// Mean absolute relative difference across pairs, in percent — the CGM
    /// literature's "MARD". Lower is better.
    let meanAbsoluteRelativeDifferencePercent: Double
    /// Mean absolute difference across pairs, in mg/dL.
    let meanAbsoluteDifferenceMgdL: Double
    /// Fraction of pairs meeting the "15/15" accuracy criterion used by
    /// ISO 15197:2013 for meters: the sensor value is within ±15 mg/dL of the
    /// reference when the reference is below 100 mg/dL, and within ±15 % of the
    /// reference when it is 100 mg/dL or above (boundaries inclusive).
    let withinISO15197Fraction: Double
}

/// Estimates how well the user's sensor agrees with their own finger-stick and
/// manually entered meter values — a personal, informational figure, not a
/// clinical accuracy rating.
///
/// Pure and deterministic. Reference readings (`.fingerstick` and `.manual`
/// measurement types) are paired one-to-one with `.cgm` readings taken within
/// ±15 minutes: all in-window combinations are ranked by time gap and assigned
/// greedily nearest-first, so the globally closest pairs win and no reading —
/// reference or sensor — is used twice. `.laboratory` values are a different
/// comparison (plasma vs interstitial timing) and `.calibration` values feed
/// the sensor itself, so both are excluded. For each pair the absolute relative
/// difference is |cgm − ref| / ref.
///
/// Conflict-superseded readings (`isActive == false`) are deliberately
/// *included*: a finger stick logged moments after a sensor point typically
/// loses conflict resolution to it, and that is exactly the comparison pair
/// wanted here.
enum SensorAccuracyAnalyzer {
    static let defaultWindowMinutes: Double = 15
    static let minimumPairs = 5

    static func analyze(
        _ readings: [GlucoseReading],
        windowMinutes: Double = defaultWindowMinutes
    ) -> SensorAccuracyResult? {
        let references = readings.filter {
            ($0.measurementType == .fingerstick || $0.measurementType == .manual)
                && $0.valueMgdL > 0
        }
        let sensor = readings.filter { $0.measurementType == .cgm }
        guard !references.isEmpty, !sensor.isEmpty else { return nil }

        let window = windowMinutes * 60

        // Every in-window (reference, sensor) combination, then a greedy
        // nearest-first assignment. Ties break on timestamps so the result
        // never depends on input order.
        struct Candidate {
            let referenceIndex: Int
            let sensorIndex: Int
            let gap: TimeInterval
        }
        var candidates: [Candidate] = []
        for (ri, reference) in references.enumerated() {
            for (si, cgm) in sensor.enumerated() {
                let gap = abs(cgm.timestamp.timeIntervalSince(reference.timestamp))
                if gap <= window {
                    candidates.append(Candidate(referenceIndex: ri, sensorIndex: si, gap: gap))
                }
            }
        }
        candidates.sort {
            if $0.gap != $1.gap { return $0.gap < $1.gap }
            let ta = references[$0.referenceIndex].timestamp
            let tb = references[$1.referenceIndex].timestamp
            if ta != tb { return ta < tb }
            return sensor[$0.sensorIndex].timestamp < sensor[$1.sensorIndex].timestamp
        }

        var usedReferences = Set<Int>()
        var usedSensor = Set<Int>()
        var pairs: [(referenceMgdL: Double, cgmMgdL: Double)] = []
        for candidate in candidates {
            guard !usedReferences.contains(candidate.referenceIndex),
                  !usedSensor.contains(candidate.sensorIndex) else { continue }
            usedReferences.insert(candidate.referenceIndex)
            usedSensor.insert(candidate.sensorIndex)
            pairs.append((
                references[candidate.referenceIndex].valueMgdL,
                sensor[candidate.sensorIndex].valueMgdL
            ))
        }
        guard pairs.count >= minimumPairs else { return nil }

        let count = Double(pairs.count)
        let sumAbsolute = pairs.reduce(0.0) { $0 + abs($1.cgmMgdL - $1.referenceMgdL) }
        let sumRelative = pairs.reduce(0.0) { $0 + abs($1.cgmMgdL - $1.referenceMgdL) / $1.referenceMgdL }
        let withinCount = pairs.filter {
            meetsFifteenFifteen(referenceMgdL: $0.referenceMgdL, cgmMgdL: $0.cgmMgdL)
        }.count

        return SensorAccuracyResult(
            pairCount: pairs.count,
            meanAbsoluteRelativeDifferencePercent: sumRelative / count * 100,
            meanAbsoluteDifferenceMgdL: sumAbsolute / count,
            withinISO15197Fraction: Double(withinCount) / count
        )
    }

    /// The 15/15 criterion: |cgm − ref| ≤ 15 mg/dL when the reference is below
    /// 100 mg/dL, |cgm − ref| ≤ 15 % of the reference otherwise. Inclusive at
    /// both boundaries.
    static func meetsFifteenFifteen(referenceMgdL: Double, cgmMgdL: Double) -> Bool {
        let difference = abs(cgmMgdL - referenceMgdL)
        return referenceMgdL < 100
            ? difference <= 15
            : difference <= 0.15 * referenceMgdL
    }
}
