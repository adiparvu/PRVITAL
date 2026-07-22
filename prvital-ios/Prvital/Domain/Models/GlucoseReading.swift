import Foundation
import SwiftData

/// A single glucose value from any source.
///
/// Stored canonically in **mg/dL** (`valueMgdL`) so a value is unit-independent;
/// the display unit is a presentation concern resolved through `GlucoseUnit`.
/// Every stored property carries a default, and there are no unique constraints,
/// so the model is safe to back with a CloudKit private database.
@Model
final class GlucoseReading: MedicalRecord {
    // A time index turns every windowed query (Dashboard, Insights, Logbook,
    // widgets) from a full scan of the whole CGM history into a range lookup —
    // the difference between smooth and a watchdog kill once a multi-year import
    // lands. The compound `[isActive, timestamp]` serves the very common
    // "active readings in a window" path directly.
    #Index<GlucoseReading>([\.timestamp], [\.isActive, \.timestamp])

    // Identity & provenance
    var id: UUID = UUID()
    var userID: String?
    var sourceRaw: String = DataSource.manual.rawValue
    var deviceID: String?
    /// A source-native identifier (e.g. a Dexcom record id) used to deduplicate
    /// repeated imports of the same physical reading.
    var externalID: String?

    // Time
    var timestamp: Date = Date()
    var sensorTimestamp: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timeZoneIdentifier: String = TimeZone.current.identifier

    // Value
    var valueMgdL: Double = 0
    var trendRaw: String?
    var measurementTypeRaw: String = GlucoseMeasurementType.manual.rawValue
    /// Source-reported reliability in 0...1 (CGM warm-up, signal loss, etc.).
    var confidence: Double?

    // Deterministic conflict resolution
    /// Identifier of the cluster of near-simultaneous readings this belongs to.
    var conflictGroupID: UUID?
    /// Whether this reading is the one surfaced to the user. Losing readings are
    /// never deleted — they remain queryable as alternatives.
    var isActive: Bool = true
    /// Human-readable reason the active reading in the group was selected.
    var resolutionReason: String?

    var recordType: RecordType { .glucose }

    // Typed accessors over the persisted raw values.
    var source: DataSource {
        get { DataSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var trend: GlucoseTrend? {
        get { trendRaw.flatMap(GlucoseTrend.init(rawValue:)) }
        set { trendRaw = newValue?.rawValue }
    }
    var measurementType: GlucoseMeasurementType {
        get { GlucoseMeasurementType(rawValue: measurementTypeRaw) ?? .manual }
        set { measurementTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        valueMgdL: Double,
        timestamp: Date = Date(),
        source: DataSource = .manual,
        measurementType: GlucoseMeasurementType = .manual,
        trend: GlucoseTrend? = nil,
        sensorTimestamp: Date? = nil,
        confidence: Double? = nil,
        deviceID: String? = nil,
        externalID: String? = nil,
        userID: String? = nil,
        timeZone: TimeZone = .current
    ) {
        self.id = id
        self.valueMgdL = valueMgdL
        self.timestamp = timestamp
        self.sourceRaw = source.rawValue
        self.measurementTypeRaw = measurementType.rawValue
        self.trendRaw = trend?.rawValue
        self.sensorTimestamp = sensorTimestamp
        self.confidence = confidence
        self.deviceID = deviceID
        self.externalID = externalID
        self.userID = userID
        self.timeZoneIdentifier = timeZone.identifier
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }

    /// The value converted to the requested display unit.
    func value(in unit: GlucoseUnit) -> Double { unit.fromMgdL(valueMgdL) }
}
