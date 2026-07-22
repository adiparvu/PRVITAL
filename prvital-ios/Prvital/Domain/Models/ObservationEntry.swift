import Foundation
import SwiftData

/// A contextual note for a moment or a day (illness, stress, sleep…), which the
/// user reviews alongside glucose to explain out-of-range patterns.
@Model
final class ObservationEntry: MedicalRecord {
    /// Time index so windowed queries skip a full-table scan after a big import.
    #Index<ObservationEntry>([\.timestamp])

    var id: UUID = UUID()
    var userID: String?
    var sourceRaw: String = DataSource.manual.rawValue
    var deviceID: String?
    var externalID: String?

    var timestamp: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// Selected tags, stored as raw strings for CloudKit-friendly persistence.
    var tagsRaw: [String] = []
    var text: String?

    var recordType: RecordType { .observation }

    var source: DataSource {
        get { DataSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var tags: [ObservationTag] {
        get { tagsRaw.compactMap(ObservationTag.init(rawValue:)) }
        set { tagsRaw = newValue.map(\.rawValue) }
    }

    init(
        id: UUID = UUID(),
        tags: [ObservationTag] = [],
        text: String? = nil,
        timestamp: Date = Date(),
        source: DataSource = .manual,
        timeZone: TimeZone = .current
    ) {
        self.id = id
        self.tagsRaw = tags.map(\.rawValue)
        self.text = text
        self.timestamp = timestamp
        self.sourceRaw = source.rawValue
        self.timeZoneIdentifier = timeZone.identifier
        self.createdAt = timestamp
        self.updatedAt = timestamp
    }
}
