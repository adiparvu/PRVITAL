import Foundation

// MARK: - Parsed model (pure, no SwiftData)

/// One record decoded from a Prvital CSV row, in a SwiftData-free form so the
/// parser can be exercised in isolation by unit tests.
enum ParsedRecord: Equatable {
    /// Glucose is normalised to **mg/dL** on the way in, regardless of the unit
    /// column, so the rest of the app stays unit-independent.
    case glucose(mgdL: Double, measurement: GlucoseMeasurementType, trend: GlucoseTrend?)
    case insulin(units: Double, type: InsulinType, context: InsulinDoseContext, name: String?)
    case carbs(grams: Double, meal: MealType, food: String?)
    case activity(type: ActivityType, minutes: Int, intensity: ActivityIntensity)
    case observation(tags: [ObservationTag], text: String?)
}

/// A single row ready to be written through `EntryStore`.
struct ParsedRow: Equatable {
    var timestamp: Date
    /// The source named in the CSV. Imports are written as `.manual` regardless
    /// (see `CSVGlucoseImporter`); this is retained for provenance / testing.
    var source: DataSource
    var record: ParsedRecord
}

/// The outcome of parsing a whole CSV document.
struct CSVParseResult: Equatable {
    var rows: [ParsedRow]
    /// Data rows that could not be understood (bad timestamp, unknown type,
    /// non-numeric value, too few columns). Header / blank / comment lines are
    /// ignored and are **not** counted here.
    var skipped: Int
}

/// What an import did: how many records were written and how many rows skipped.
struct ImportSummary: Equatable {
    var imported: Int
    var skipped: Int
    var total: Int { imported + skipped }
}

// MARK: - Pure parser

/// Parses the CSV that `ExportService` writes — the exact
/// `record_type,timestamp_utc,source,value,unit,detail` layout — so a Prvital
/// export round-trips. Deliberately free of SwiftData and file I/O so it is
/// fully unit-testable off the main actor.
enum CSVImportParser {
    /// The " · " separator `ExportService` joins the `detail` column with
    /// (U+00B7 flanked by spaces).
    private static let detailSeparator = " \u{00B7} "

    /// Decodes a CSV document into typed rows plus a skip count.
    static func parse(_ text: String) -> CSVParseResult {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(identifier: "UTC")
        iso.formatOptions = [.withInternetDateTime]

        var rows: [ParsedRow] = []
        var skipped = 0

        for fields in tokenize(text) {
            if isBlank(fields) { continue }
            let head = fields[0].trimmingCharacters(in: .whitespaces)
            if head.hasPrefix("#") { continue }        // sensitivity-notice comment
            if head == "record_type" { continue }       // header row
            if let row = parseRow(fields, iso: iso) {
                rows.append(row)
            } else {
                skipped += 1
            }
        }
        return CSVParseResult(rows: rows, skipped: skipped)
    }

    // MARK: Row decoding

    private static func parseRow(_ fields: [String], iso: ISO8601DateFormatter) -> ParsedRow? {
        guard fields.count >= 6 else { return nil }
        guard let type = RecordType(rawValue: fields[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        guard let timestamp = iso.date(from: fields[1].trimmingCharacters(in: .whitespaces)) else { return nil }

        let source = DataSource.allCases.first { $0.displayName == fields[2] } ?? .manual
        let valueField = fields[3]
        let unit = fields[4].trimmingCharacters(in: .whitespaces)
        let parts = splitDetail(fields[5])
        func part(_ i: Int) -> String? { i < parts.count ? parts[i] : nil }

        let record: ParsedRecord
        switch type {
        case .glucose:
            guard let raw = number(from: valueField) else { return nil }
            let mgdL = (GlucoseUnit(rawValue: unit) ?? .mgdL).toMgdL(raw)
            let measurement = part(0).flatMap { p in GlucoseMeasurementType.allCases.first { $0.label == p } } ?? .manual
            let trend = part(1).flatMap { p in GlucoseTrend.allCases.first { $0.label == p } }
            record = .glucose(mgdL: mgdL, measurement: measurement, trend: trend)

        case .insulin:
            guard let units = number(from: valueField) else { return nil }
            let insulinType = part(0).flatMap { p in InsulinType.allCases.first { $0.label == p } } ?? .rapidActing
            let context = part(1).flatMap { p in InsulinDoseContext.allCases.first { $0.label == p } } ?? .mealBolus
            let name = part(2)
            record = .insulin(units: units, type: insulinType, context: context, name: name)

        case .carbohydrate:
            guard let grams = number(from: valueField) else { return nil }
            let meal = part(0).flatMap { p in MealType.allCases.first { $0.label == p } } ?? .lunch
            let food = parts.count > 1 ? parts[1...].joined(separator: detailSeparator) : nil
            record = .carbs(grams: grams, meal: meal, food: food)

        case .activity:
            guard let minutes = number(from: valueField) else { return nil }
            let activity = part(0).flatMap { p in ActivityType.allCases.first { $0.label == p } } ?? .walking
            let intensity = part(1).flatMap { p in ActivityIntensity.allCases.first { $0.label == p } } ?? .moderate
            record = .activity(type: activity, minutes: Int(minutes.rounded()), intensity: intensity)

        case .observation:
            var tags: [ObservationTag] = []
            var textParts: [String] = []
            for piece in parts {
                if let tag = ObservationTag.allCases.first(where: { $0.label == piece }) {
                    tags.append(tag)
                } else {
                    textParts.append(piece)
                }
            }
            record = .observation(tags: tags, text: textParts.isEmpty ? nil : textParts.joined(separator: detailSeparator))
        }

        return ParsedRow(timestamp: timestamp, source: source, record: record)
    }

    // MARK: Helpers

    private static func isBlank(_ fields: [String]) -> Bool {
        fields.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func splitDetail(_ detail: String) -> [String] {
        detail.isEmpty ? [] : detail.components(separatedBy: detailSeparator)
    }

    /// Parses a numeric field, tolerating the grouping / decimal separators that
    /// `.formatted()` may emit in a non-US locale.
    static func number(from raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) { return value }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: trimmed)?.doubleValue
    }

    /// A minimal RFC-4180 tokeniser: splits `text` into rows of fields, honouring
    /// double-quoted fields that may themselves contain commas, newlines and
    /// escaped `""` quotes.
    static func tokenize(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    field.append(c)
                    i += 1
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                    i += 1
                case ",":
                    endField()
                    i += 1
                case "\n":
                    endRow()
                    i += 1
                case "\r":
                    endRow()
                    i += (i + 1 < chars.count && chars[i + 1] == "\n") ? 2 : 1
                default:
                    field.append(c)
                    i += 1
                }
            }
        }
        // Flush a trailing field/row that wasn't newline-terminated.
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

// MARK: - @MainActor importer

/// Writes parsed CSV rows into the app through `EntryStore`, so deduplication,
/// the audit trail and (for glucose) Apple Health mirroring all apply exactly as
/// they do for a hand-typed entry.
///
/// Imported rows are treated as **manual** entries per the app's provenance
/// rules: glucose is stored with `source: .manual`, and insulin / carbs /
/// activity carry an "Imported" note.
@MainActor
enum CSVGlucoseImporter {
    private static let importedNote = "Imported"

    /// Parses `text` and imports every valid row, returning the counts.
    @discardableResult
    static func importCSV(_ text: String, into store: EntryStore) -> ImportSummary {
        let result = CSVImportParser.parse(text)
        return importRows(result.rows, into: store, alreadySkipped: result.skipped)
    }

    /// Inserts already-parsed rows through the `EntryStore`. `alreadySkipped`
    /// carries forward rows the parser could not decode so the summary reflects
    /// the whole document.
    @discardableResult
    static func importRows(_ rows: [ParsedRow], into store: EntryStore, alreadySkipped: Int = 0) -> ImportSummary {
        var imported = 0
        for row in rows {
            switch row.record {
            case let .glucose(mgdL, measurement, trend):
                store.addGlucose(mgdL: mgdL, timestamp: row.timestamp,
                                 measurementType: measurement, trend: trend, source: .manual)
            case let .insulin(units, type, context, name):
                store.addInsulin(units: units, timestamp: row.timestamp, type: type,
                                 name: name, context: context, note: importedNote)
            case let .carbs(grams, meal, food):
                store.addCarbs(grams: grams, timestamp: row.timestamp,
                               mealType: meal, foodDescription: food, note: importedNote)
            case let .activity(type, minutes, intensity):
                store.addActivity(type: type, start: row.timestamp,
                                  durationSeconds: minutes * 60, intensity: intensity, note: importedNote)
            case let .observation(tags, text):
                store.addObservation(tags: tags, text: text, timestamp: row.timestamp)
            }
            imported += 1
        }
        return ImportSummary(imported: imported, skipped: alreadySkipped)
    }
}
