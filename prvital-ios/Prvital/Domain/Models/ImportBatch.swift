import Foundation
import SwiftData

/// One CSV import, recorded so the user can review what a file brought in and
/// **undo it in one tap** if they loaded the wrong export. Every record inserted
/// by the import carries this batch's `id` in its `importBatchID`, so deleting
/// the batch can remove exactly — and only — that file's data.
@Model
final class ImportBatch {
    var id: UUID = UUID()
    var importedAt: Date = Date()
    /// The source file's name, shown in the list (e.g. "Clarity_export.csv").
    var filename: String?
    /// The detected format's display name (e.g. "Dexcom Clarity").
    var formatName: String = ""

    // Per-type counts, so the row can summarise the file without re-querying.
    var glucoseCount: Int = 0
    var insulinCount: Int = 0
    var carbCount: Int = 0
    var activityCount: Int = 0
    var observationCount: Int = 0
    /// Rows the file contained that were already present and skipped as duplicates.
    var duplicateCount: Int = 0

    init(id: UUID = UUID(), importedAt: Date = Date(), filename: String? = nil, formatName: String = "") {
        self.id = id
        self.importedAt = importedAt
        self.filename = filename
        self.formatName = formatName
    }

    var totalCount: Int {
        glucoseCount + insulinCount + carbCount + activityCount + observationCount
    }
}
