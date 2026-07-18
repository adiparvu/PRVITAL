import Foundation

/// The **normalization layer**: the single place that maps an integration-layer
/// `NormalizedGlucoseSample` onto a persisted `GlucoseReading`. Keeping the
/// mapping here means every source lands in storage identically.
enum GlucoseNormalizer {
    static func reading(from sample: NormalizedGlucoseSample) -> GlucoseReading {
        GlucoseReading(
            valueMgdL: sample.valueMgdL,
            timestamp: sample.timestamp,
            source: sample.source,
            measurementType: sample.measurementType,
            trend: sample.trend,
            sensorTimestamp: sample.sensorTimestamp,
            confidence: sample.confidence,
            deviceID: sample.deviceID,
            externalID: sample.id
        )
    }
}
