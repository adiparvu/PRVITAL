import Foundation
import SwiftData

/// Immutable-by-convention entry in the privacy audit trail.
///
/// Deliberately **does not** store medical values — only the fact that a
/// sensitive operation happened, when, to which source, with what result, and
/// whether the user confirmed it. This keeps the trail useful for traceability
/// without turning it into a second copy of the health data.
@Model
final class PrivacyAuditRecord {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var actionTypeRaw: String = AuditActionType.dataRead.rawValue
    var dataSourceRaw: String?
    var userConfirmation: Bool = false
    /// A stable, non-identifying device tag (see `DeviceIdentity`).
    var deviceIdentifier: String = ""
    var resultRaw: String = AuditResult.success.rawValue
    /// Optional non-medical context, e.g. "resolved 2 conflicting readings".
    var detail: String?

    var actionType: AuditActionType {
        get { AuditActionType(rawValue: actionTypeRaw) ?? .dataRead }
        set { actionTypeRaw = newValue.rawValue }
    }
    var dataSource: DataSource? {
        get { dataSourceRaw.flatMap(DataSource.init(rawValue:)) }
        set { dataSourceRaw = newValue?.rawValue }
    }
    var result: AuditResult {
        get { AuditResult(rawValue: resultRaw) ?? .success }
        set { resultRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionType: AuditActionType,
        dataSource: DataSource? = nil,
        userConfirmation: Bool = false,
        deviceIdentifier: String = "",
        result: AuditResult = .success,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actionTypeRaw = actionType.rawValue
        self.dataSourceRaw = dataSource?.rawValue
        self.userConfirmation = userConfirmation
        self.deviceIdentifier = deviceIdentifier
        self.resultRaw = result.rawValue
        self.detail = detail
    }
}

/// The current state of one consent scope. One row per scope; updated in place
/// as the user grants or revokes, with the change mirrored into the audit trail.
@Model
final class ConsentRecord {
    var id: UUID = UUID()
    var scopeRaw: String = ""
    var granted: Bool = false
    var updatedAt: Date = Date()
    /// Version of the consent copy the user agreed to, for re-consent flows.
    var policyVersion: String = "1.0.0"

    var scope: ConsentScope? {
        get { ConsentScope(rawValue: scopeRaw) }
        set { scopeRaw = newValue?.rawValue ?? "" }
    }

    init(
        id: UUID = UUID(),
        scope: ConsentScope,
        granted: Bool = false,
        updatedAt: Date = Date(),
        policyVersion: String = "1.0.0"
    ) {
        self.id = id
        self.scopeRaw = scope.rawValue
        self.granted = granted
        self.updatedAt = updatedAt
        self.policyVersion = policyVersion
    }
}
