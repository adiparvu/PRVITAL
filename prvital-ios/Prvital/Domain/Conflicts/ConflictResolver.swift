import Foundation

/// A cluster of near-simultaneous glucose readings and the deterministic
/// decision made for it. Nothing is deleted — every candidate stays queryable.
struct ConflictGroup: Identifiable, Sendable {
    let id: UUID
    let candidateIDs: [UUID]
    let activeID: UUID
    let reason: String
}

/// Outcome of a resolution pass, used for the audit trail.
struct ConflictResolutionSummary: Sendable {
    var groups: [ConflictGroup] = []
    var conflictedReadingCount: Int { groups.reduce(0) { $0 + $1.candidateIDs.count } }
    var groupCount: Int { groups.count }
}

/// Resolves conflicts between glucose readings from different sources using a
/// single, predictable, repeatable strategy.
///
/// Guarantees (from the product spec):
///   • No original medical value is ever deleted.
///   • Every conflict is preserved for the audit trail.
///   • Exactly one value per cluster is marked active for display.
///   • Alternatives remain available (`isActive == false`, same `conflictGroupID`).
///   • The reason for the selection is human-readable and reproducible.
///
/// The comparison order is fully deterministic:
///   1. the user's **primary source** preference (`sourcePriority`),
///   2. measurement-type authority (lab > finger-stick > CGM > calibration > manual),
///   3. reported **confidence**,
///   4. freshest sensor sample, then freshest capture time,
///   5. UUID — a stable final tiebreak so the result never depends on input order.
struct ConflictResolver {

    /// Readings this far apart or closer are treated as the same clinical instant.
    var window: TimeInterval = 150
    /// The user's source preference, most-trusted first.
    var sourcePriority: [DataSource]

    init(
        sourcePriority: [DataSource] = [.dexcom, .freeStyleLibre, .otherCGM, .appleHealth, .appleWatch, .manual],
        window: TimeInterval = 150
    ) {
        self.sourcePriority = sourcePriority
        self.window = window
    }

    /// Clusters and resolves in place, mutating `isActive`, `conflictGroupID`
    /// and `resolutionReason` on the passed reference-type readings.
    @discardableResult
    func resolve(_ readings: [GlucoseReading]) -> ConflictResolutionSummary {
        var summary = ConflictResolutionSummary()
        let ordered = readings.sorted { $0.timestamp < $1.timestamp }
        guard var anchor = ordered.first else { return summary }

        var cluster: [GlucoseReading] = []
        func flush() {
            defer { cluster.removeAll() }
            guard let group = decide(cluster) else {
                // Singleton: no conflict.
                cluster.first.map { reset($0) }
                return
            }
            summary.groups.append(group)
        }

        for reading in ordered {
            if reading.timestamp.timeIntervalSince(anchor.timestamp) <= window {
                cluster.append(reading)
            } else {
                flush()
                anchor = reading
                cluster = [reading]
            }
        }
        flush()
        return summary
    }

    /// Resets a non-conflicted reading to the default active state.
    private func reset(_ reading: GlucoseReading) {
        reading.isActive = true
        reading.conflictGroupID = nil
        reading.resolutionReason = nil
    }

    /// Decides a cluster; returns `nil` for singletons (no conflict).
    private func decide(_ cluster: [GlucoseReading]) -> ConflictGroup? {
        guard cluster.count > 1 else { return nil }
        let groupID = UUID()
        let winner = cluster.min(by: precedes) ?? cluster[0]
        let reason = explanation(winner: winner, over: cluster)

        for reading in cluster {
            reading.conflictGroupID = groupID
            reading.isActive = (reading.id == winner.id)
            reading.resolutionReason = reading.id == winner.id ? reason : "Superseded — \(reason)"
        }
        return ConflictGroup(
            id: groupID,
            candidateIDs: cluster.map(\.id),
            activeID: winner.id,
            reason: reason
        )
    }

    /// `true` when `a` should rank ahead of `b` (a is the stronger candidate).
    private func precedes(_ a: GlucoseReading, _ b: GlucoseReading) -> Bool {
        let ra = sourceRank(a.source), rb = sourceRank(b.source)
        if ra != rb { return ra < rb }

        let ma = measurementAuthority(a.measurementType)
        let mb = measurementAuthority(b.measurementType)
        if ma != mb { return ma > mb }

        let ca = a.confidence ?? 0, cb = b.confidence ?? 0
        if ca != cb { return ca > cb }

        let sa = a.sensorTimestamp ?? a.timestamp
        let sb = b.sensorTimestamp ?? b.timestamp
        if sa != sb { return sa > sb }

        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    private func sourceRank(_ source: DataSource) -> Int {
        sourcePriority.firstIndex(of: source) ?? sourcePriority.count
    }

    private func measurementAuthority(_ type: GlucoseMeasurementType) -> Int {
        switch type {
        case .laboratory: return 5
        case .fingerstick: return 4
        case .cgm: return 3
        case .calibration: return 2
        case .manual: return 1
        }
    }

    private func explanation(winner: GlucoseReading, over cluster: [GlucoseReading]) -> String {
        let others = cluster.filter { $0.id != winner.id }.map { $0.source.displayName }
        let uniqueOthers = Array(Set(others)).sorted().joined(separator: ", ")
        let rank = sourceRank(winner.source)
        let isPrimary = rank == 0
        let basis = isPrimary ? "primary source" : "higher-priority source"
        if uniqueOthers.isEmpty {
            return "Selected \(winner.source.displayName) (\(basis))."
        }
        return "Selected \(winner.source.displayName) (\(basis)) over \(uniqueOthers)."
    }
}
