import Foundation

// MARK: - Shared record contract
//
// A common surface over the five medical record types so the domain, audit and
// export layers can treat them uniformly. Concrete types are SwiftData
// `@Model` classes; this protocol only exposes identity, provenance and time.

protocol MedicalRecord: Identifiable {
    var id: UUID { get }
    var recordType: RecordType { get }
    var source: DataSource { get set }
    var deviceID: String? { get set }
    /// The clinically meaningful instant for this record (UTC internally).
    var timestamp: Date { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    /// IANA identifier of the time zone the record was captured in, so the UI
    /// can render the original local time even after the device moves.
    var timeZoneIdentifier: String { get set }
}

extension MedicalRecord {
    var captureTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

// MARK: - Audit & consent vocabularies

/// Sensitive operations recorded in the privacy audit trail.
enum AuditActionType: String, Codable, CaseIterable, Sendable {
    case sourceAccess = "source_access"
    case dataRead = "data_read"
    case sync
    case export
    case manualEdit = "manual_edit"
    case permissionChange = "permission_change"
    case conflictResolution = "conflict_resolution"
    case dataDeletion = "data_deletion"

    var label: String {
        switch self {
        case .sourceAccess: return "Source access"
        case .dataRead: return "Data read"
        case .sync: return "Sync"
        case .export: return "Export"
        case .manualEdit: return "Manual edit"
        case .permissionChange: return "Permission change"
        case .conflictResolution: return "Conflict resolved"
        case .dataDeletion: return "Data deleted"
        }
    }

    var symbol: String {
        switch self {
        case .sourceAccess: return "antenna.radiowaves.left.and.right"
        case .dataRead: return "eye"
        case .sync: return "arrow.triangle.2.circlepath"
        case .export: return "square.and.arrow.up"
        case .manualEdit: return "pencil"
        case .permissionChange: return "lock.rotation"
        case .conflictResolution: return "arrow.triangle.merge"
        case .dataDeletion: return "trash"
        }
    }
}

/// The outcome recorded for an audited operation.
enum AuditResult: String, Codable, CaseIterable, Sendable {
    case granted
    case denied
    case success
    case failure
    case revoked

    var label: String { rawValue.capitalized }
}

/// Distinct consent scopes. Each is requested and revoked independently, so the
/// user is never asked to grant everything at once.
enum ConsentScope: String, Codable, CaseIterable, Sendable, Identifiable {
    case healthKit = "health_kit"
    case appleWatch = "apple_watch"
    case externalCGM = "external_cgm"
    case cloudSync = "cloud_sync"
    case dataExport = "data_export"
    case aiFeatures = "ai_features"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthKit: return "Apple Health"
        case .appleWatch: return "Apple Watch"
        case .externalCGM: return "CGM sensors"
        case .cloudSync: return "iCloud sync"
        case .dataExport: return "Data export"
        case .aiFeatures: return "Intelligent features"
        }
    }

    /// Plain-language explanation shown before the system permission prompt.
    var rationale: String {
        switch self {
        case .healthKit:
            return "Read glucose, insulin, carbohydrate and workout samples already in Apple Health, and write the entries you log here back to it. Data stays on your device and in your private Health store."
        case .appleWatch:
            return "Show your glucose and let you log insulin and carbs from your wrist. Nothing leaves your paired devices."
        case .externalCGM:
            return "Connect a Dexcom or FreeStyle Libre sensor so readings arrive automatically. You choose which sensor is your primary source."
        case .cloudSync:
            return "Keep your journal in sync across your devices through your private iCloud database. Apple cannot read the contents; only your devices can."
        case .dataExport:
            return "Generate PDF and CSV reports for your care team. Files are created on-device and shared only through the system share sheet."
        case .aiFeatures:
            return "Let on-device intelligence highlight patterns and summarise your day. Suggestions are never medical decisions, and your data is never used to train models."
        }
    }

    var symbol: String {
        switch self {
        case .healthKit: return "heart.text.square"
        case .appleWatch: return "applewatch"
        case .externalCGM: return "sensor.tag.radiowaves.forward"
        case .cloudSync: return "icloud"
        case .dataExport: return "square.and.arrow.up"
        case .aiFeatures: return "sparkles"
        }
    }
}
