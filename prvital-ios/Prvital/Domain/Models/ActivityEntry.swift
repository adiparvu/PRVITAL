import Foundation
import SwiftData

/// A physical-activity session.
@Model
final class ActivityEntry: MedicalRecord {
    var id: UUID = UUID()
    var userID: String?
    var sourceRaw: String = DataSource.manual.rawValue
    var deviceID: String?
    var externalID: String?

    /// `timestamp` mirrors `startTimestamp` to satisfy `MedicalRecord`.
    var timestamp: Date = Date()
    var startTimestamp: Date = Date()
    var endTimestamp: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timeZoneIdentifier: String = TimeZone.current.identifier

    var activityTypeRaw: String = ActivityType.walking.rawValue
    var durationSeconds: Int = 0
    var intensityRaw: String = ActivityIntensity.moderate.rawValue
    var caloriesBurned: Double?
    var distanceMeters: Double?
    var note: String?

    var recordType: RecordType { .activity }

    var source: DataSource {
        get { DataSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRaw) ?? .walking }
        set { activityTypeRaw = newValue.rawValue }
    }
    var intensity: ActivityIntensity {
        get { ActivityIntensity(rawValue: intensityRaw) ?? .moderate }
        set { intensityRaw = newValue.rawValue }
    }

    var durationMinutes: Int { durationSeconds / 60 }

    init(
        id: UUID = UUID(),
        activityType: ActivityType = .walking,
        startTimestamp: Date = Date(),
        durationSeconds: Int,
        intensity: ActivityIntensity = .moderate,
        caloriesBurned: Double? = nil,
        distanceMeters: Double? = nil,
        source: DataSource = .manual,
        note: String? = nil,
        timeZone: TimeZone = .current
    ) {
        self.id = id
        self.activityTypeRaw = activityType.rawValue
        self.startTimestamp = startTimestamp
        self.timestamp = startTimestamp
        self.endTimestamp = startTimestamp.addingTimeInterval(TimeInterval(durationSeconds))
        self.durationSeconds = durationSeconds
        self.intensityRaw = intensity.rawValue
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
        self.sourceRaw = source.rawValue
        self.note = note
        self.timeZoneIdentifier = timeZone.identifier
        self.createdAt = startTimestamp
        self.updatedAt = startTimestamp
    }
}
