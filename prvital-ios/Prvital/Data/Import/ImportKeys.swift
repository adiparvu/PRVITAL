import Foundation

/// Deterministic identity for an imported record, so re-importing the same file
/// — or two Clarity/LibreView exports whose date ranges overlap — never creates
/// duplicates. The key folds the source, the whole-second timestamp, the record
/// kind and the value, which together uniquely identify a CGM/log row across
/// repeated exports.
///
/// Pure and deterministic, so the dedup logic is fully unit-testable without
/// SwiftData.
enum ImportKeys {
    /// Prefix marking an `externalID` that this bulk importer minted (as opposed
    /// to a live-sync id), so the dedup pre-fetch can recognise its own keys.
    static let prefix = "import:"

    static func externalID(for record: ParsedRecord, source: DataSource, timestamp: Date) -> String {
        let epoch = Int(timestamp.timeIntervalSince1970.rounded())
        let kindValue: String
        switch record {
        case let .glucose(mgdL, _, _):
            kindValue = "g:\(Int(mgdL.rounded()))"
        case let .insulin(units, type, _, _):
            kindValue = "i:\(type.rawValue):\(twoDecimals(units))"
        case let .carbs(grams, _, _):
            kindValue = "c:\(twoDecimals(grams))"
        case let .activity(type, minutes, _):
            kindValue = "a:\(type.rawValue):\(minutes)"
        case .observation:
            kindValue = "o"
        }
        return "\(prefix)\(source.rawValue):\(epoch):\(kindValue)"
    }

    private static func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// A parsed row paired with the stable id the importer will store on it.
struct KeyedImportRow: Equatable {
    var row: ParsedRow
    var externalID: String
}

/// The decision of which rows to actually insert, given what's already stored.
struct BulkImportPlan: Equatable {
    var toInsert: [KeyedImportRow]
    /// Rows dropped because an identical record already exists (in the store or
    /// earlier in this same batch).
    var duplicates: Int
}

/// Decides, purely, which parsed rows are new. De-duplicates both against the
/// set of `existing` import ids and within the incoming batch itself (a single
/// export can list the same instant twice).
enum BulkImportPlanner {
    static func plan(rows: [ParsedRow], existing: Set<String>) -> BulkImportPlan {
        var seen = existing
        var toInsert: [KeyedImportRow] = []
        var duplicates = 0
        for row in rows {
            let id = ImportKeys.externalID(for: row.record, source: row.source, timestamp: row.timestamp)
            if seen.contains(id) {
                duplicates += 1
                continue
            }
            seen.insert(id)
            toInsert.append(KeyedImportRow(row: row, externalID: id))
        }
        return BulkImportPlan(toInsert: toInsert, duplicates: duplicates)
    }
}
