import Foundation

// MARK: - Format

/// The CSV layouts the unified "Import from file" flow understands.
/// `prvital` is the app's own export (decoded by `CSVImportParser`); the other
/// two are the report exports patients can download from Dexcom Clarity and
/// LibreView (FreeStyle Libre). Detected purely from the header signature.
enum ExternalCSVFormat: Equatable, Sendable {
    case dexcomClarity
    case libreView
    case prvital

    /// Shown in the import result alert ("Imported 1,240 records from Dexcom Clarity").
    var displayName: String {
        switch self {
        case .dexcomClarity: return "Dexcom Clarity"
        case .libreView: return "LibreView"
        case .prvital: return "Prvital"
        }
    }
}

// MARK: - Pure parser

/// Detects and decodes third-party CGM exports — Dexcom Clarity and LibreView
/// CSVs — into the same `ParsedRow` model the Prvital CSV importer uses, so all
/// three formats funnel through the one `CSVGlucoseImporter.importRows(_:into:alreadySkipped:)`
/// write path.
///
/// Deduplication is deliberately **not** implemented here: rows are written
/// through `EntryStore`, whose glucose conflict resolution (`ConflictResolver`
/// over a ±10-minute cluster) already collapses duplicates against readings
/// synced from Dexcom Share / LibreLinkUp / Nightscout or a previous import.
///
/// Free of SwiftData and file I/O so it is fully unit-testable.
enum ExternalCSVImporter {

    // MARK: Detection

    /// How many leading rows are searched for a recognisable header. Clarity
    /// puts the header on line 1; LibreView puts one or two metadata lines
    /// before it; a Prvital export may start with a "#" notice.
    private static let headerSearchLimit = 10

    /// Identifies which export produced `text` by its header row, or `nil` if
    /// none of the known signatures match.
    static func detectFormat(_ text: String) -> ExternalCSVFormat? {
        detectFormat(rows: CSVImportParser.tokenize(text))
    }

    private static func detectFormat(rows: [[String]]) -> ExternalCSVFormat? {
        for fields in rows.prefix(headerSearchLimit) {
            let trimmed = fields.map(trim)
            if trimmed.first == "record_type" { return .prvital }
            if isClarityHeader(trimmed) { return .dexcomClarity }
            if isLibreViewHeader(trimmed) { return .libreView }
        }
        return nil
    }

    /// Dexcom Clarity export: header row 1 is
    /// `Index,Timestamp (YYYY-MM-DDThh:mm:ss),Event Type,Event Subtype,…,Glucose Value (mg/dL),Insulin Value (u),Carb Value (grams),…`
    /// (the glucose column reads `(mmol/L)` on mmol accounts). Matched by
    /// prefix so minor unit / wording revisions keep detecting.
    private static func isClarityHeader(_ fields: [String]) -> Bool {
        fields.contains { $0.hasPrefix("Timestamp (") }
            && fields.contains("Event Type")
            && fields.contains { $0.hasPrefix("Glucose Value (") }
    }

    /// LibreView export: line 1 (and sometimes 2) is patient/report metadata;
    /// the header row contains
    /// `Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mg/dL,Scan Glucose mg/dL,…`
    /// (`mmol/L` on mmol accounts).
    private static func isLibreViewHeader(_ fields: [String]) -> Bool {
        fields.contains("Device Timestamp")
            && fields.contains("Record Type")
            && fields.contains { $0.hasPrefix("Historic Glucose") }
    }

    // MARK: Parsing

    /// Detects the format and decodes the whole document in one pass.
    /// Returns `nil` when the file matches none of the known layouts.
    static func parse(_ text: String) -> (format: ExternalCSVFormat, result: CSVParseResult)? {
        let rows = CSVImportParser.tokenize(text)
        guard let format = detectFormat(rows: rows) else { return nil }
        switch format {
        case .prvital: return (.prvital, CSVImportParser.parse(text))
        case .dexcomClarity: return (.dexcomClarity, parseClarity(rows))
        case .libreView: return (.libreView, parseLibreView(rows))
        }
    }

    // MARK: Dexcom Clarity

    /// Decodes a Clarity export. Rows whose Event Type is `EGV` (sensor
    /// glucose) or `Calibration` (meter value entered for calibration) become
    /// glucose records, `Insulin` and `Carbs` rows become doses and meals.
    /// The leading account/device/alert rows (`FirstName`, `LastName`,
    /// `Device`, `Alert`, …) are file metadata and are ignored without being
    /// counted as skipped; `Low`/`High` sensor-clamp placeholders in the
    /// glucose column carry no numeric value and **are** counted as skipped.
    private static func parseClarity(_ rows: [[String]]) -> CSVParseResult {
        guard let headerIndex = rows.firstIndex(where: { isClarityHeader($0.map(trim)) }) else {
            return CSVParseResult(rows: [], skipped: 0)
        }
        let header = rows[headerIndex].map(trim)
        func column(prefixed prefix: String) -> Int? {
            header.firstIndex { $0.hasPrefix(prefix) }
        }
        guard let timestampCol = column(prefixed: "Timestamp ("),
              let glucoseCol = column(prefixed: "Glucose Value (") else {
            return CSVParseResult(rows: [], skipped: 0)
        }
        // Optional: used only for the calibration / long-acting sub-distinctions,
        // which default gracefully — so a localized "Event Type" header (which
        // wouldn't match) no longer aborts the whole import.
        let eventTypeCol = header.firstIndex(of: "Event Type")
        let subtypeCol = header.firstIndex(of: "Event Subtype")
        let insulinCol = column(prefixed: "Insulin Value")
        let carbCol = column(prefixed: "Carb")
        let durationCol = column(prefixed: "Duration")
        let unit: GlucoseUnit = header[glucoseCol].contains("mmol") ? .mmolL : .mgdL

        // Clarity timestamps ("2024-06-01T08:03:12") carry no timezone: the
        // export is written in the local time the account displays in. We
        // assume that matches this device's current timezone — the closest
        // possible reading without zone information in the file.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var parsed: [ParsedRow] = []
        var skipped = 0

        for raw in rows[(headerIndex + 1)...] {
            let fields = raw.map(trim)
            if fields.allSatisfy(\.isEmpty) { continue }
            func field(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index]
            }

            // Real Clarity records always carry a timestamp; the leading
            // account/device/alert metadata rows don't — and some (e.g. an Alert
            // row) even put a threshold value in the glucose column. Guard on the
            // timestamp first so those metadata rows are ignored (not counted, and
            // not mistaken for readings) before we classify by value column.
            guard let timestamp = formatter.date(from: field(timestampCol)) else { continue }

            // Classify by which numeric VALUE column is populated, not by the
            // Event Type text. The EU/localized Clarity export translates the
            // Event Type/Subtype cells (e.g. German "Kohlenhydrate", French
            // "Glucides"), so an English-string switch silently dropped every
            // meal, insulin and exercise row. Each Clarity record fills exactly
            // one value column, so this is unambiguous.
            let eventType = field(eventTypeCol).lowercased()
            let glucoseText = field(glucoseCol)

            if let value = CSVImportParser.number(from: glucoseText) {
                // A calibration also carries a glucose value; keep the finger-stick
                // distinction where the (possibly localized) label makes it clear,
                // else treat it as a sensor reading.
                let isCalibration = eventType.contains("cal") || eventType.contains("kal")
                    || eventType.contains("étal") || eventType.contains("etal")
                parsed.append(ParsedRow(
                    timestamp: timestamp, source: .dexcom,
                    record: .glucose(mgdL: unit.toMgdL(value),
                                     measurement: isCalibration ? .calibration : .cgm, trend: nil)
                ))

            } else if let units = CSVImportParser.number(from: field(insulinCol)) {
                // Long-acting/basal subtype across languages ("Long-Acting",
                // "Langwirksam", "Lente", "Basal"); anything else is a bolus.
                let subtype = field(subtypeCol).lowercased()
                let isLong = subtype.contains("long") || subtype.contains("lang")
                    || subtype.contains("lent") || subtype.contains("basal")
                    || subtype.contains("lung") || subtype.contains("dług")
                parsed.append(ParsedRow(
                    timestamp: timestamp, source: .dexcom,
                    record: .insulin(units: units,
                                     type: isLong ? .longActing : .rapidActing,
                                     context: isLong ? .basal : .mealBolus,
                                     name: nil)
                ))

            } else if let grams = CSVImportParser.number(from: field(carbCol)) {
                // Clarity carries no meal label — infer it from the hour, the
                // same way Apple Health carbohydrate imports do.
                parsed.append(ParsedRow(
                    timestamp: timestamp, source: .dexcom,
                    record: .carbs(grams: grams,
                                   meal: MealTimeClassifier.mealType(for: timestamp),
                                   food: nil)
                ))

            } else if let minutes = clarityDurationMinutes(field(durationCol)), minutes > 0 {
                parsed.append(ParsedRow(
                    timestamp: timestamp, source: .dexcom,
                    record: .activity(type: .walking, minutes: minutes,
                                      intensity: clarityIntensity(field(subtypeCol)))
                ))

            } else {
                // A timestamped row we couldn't decode into any record — a
                // "Low"/"High" glucose clamp, or an event missing its value (e.g.
                // an exercise row with no duration). Count it as skipped. Account
                // metadata rows never reach here: they have no timestamp and were
                // dropped by the guard above.
                skipped += 1
            }
        }
        return CSVParseResult(rows: parsed, skipped: skipped)
    }

    /// Parses a Clarity "hh:mm:ss" (or "mm:ss") duration into whole minutes.
    static func clarityDurationMinutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let nums = parts.compactMap { $0 }
        let seconds: Int
        switch nums.count {
        case 3: seconds = nums[0] * 3600 + nums[1] * 60 + nums[2]
        case 2: seconds = nums[0] * 60 + nums[1]
        case 1: seconds = nums[0] * 60          // a bare number is taken as minutes
        default: return nil
        }
        return seconds > 0 ? max(1, Int((Double(seconds) / 60).rounded())) : nil
    }

    /// Maps a Clarity exercise subtype (Light / Medium / Heavy) to intensity.
    private static func clarityIntensity(_ subtype: String) -> ActivityIntensity {
        switch subtype.lowercased() {
        case let s where s.contains("light"): return .low
        case let s where s.contains("heav") || s.contains("intens") || s.contains("high"): return .high
        default: return .moderate
        }
    }

    // MARK: LibreView

    /// The Device Timestamp patterns LibreView writes, depending on the
    /// account's region: US-style 12-hour ("06-01-2024 08:04 AM") or EU-style
    /// 24-hour ("01-06-2024 08:04"), occasionally with slashes. The first
    /// pattern that parses **every** timestamp in the document wins, so an
    /// all-numeric day/month file can't be mis-read row by row.
    private static let libreTimestampPatterns = [
        "MM-dd-yyyy hh:mm a",
        "dd-MM-yyyy HH:mm",
        "MM/dd/yyyy hh:mm a",
        "dd/MM/yyyy HH:mm",
    ]

    /// Decodes a LibreView export. Record Type 0 (historic/automatic) and
    /// 1 (scan) are sensor glucose, 2 is a test-strip (fingerstick) value,
    /// 4 is insulin (rapid vs long decided by which units column is filled),
    /// 5 is food. Other record kinds (ketones, notes, …) count as skipped.
    private static func parseLibreView(_ rows: [[String]]) -> CSVParseResult {
        guard let headerIndex = rows.firstIndex(where: { isLibreViewHeader($0.map(trim)) }) else {
            return CSVParseResult(rows: [], skipped: 0)
        }
        let header = rows[headerIndex].map(trim)
        guard let timestampCol = header.firstIndex(of: "Device Timestamp"),
              let recordTypeCol = header.firstIndex(of: "Record Type") else {
            return CSVParseResult(rows: [], skipped: 0)
        }
        let historicCol = header.firstIndex { $0.hasPrefix("Historic Glucose") }
        let scanCol = header.firstIndex { $0.hasPrefix("Scan Glucose") }
        let stripCol = header.firstIndex { $0.hasPrefix("Strip Glucose") }
        let rapidCol = header.firstIndex(of: "Rapid-Acting Insulin (units)")
        let longCol = header.firstIndex(of: "Long-Acting Insulin (units)")
        let carbCol = header.firstIndex(of: "Carbohydrates (grams)")
        let unit: GlucoseUnit =
            (historicCol.map { header[$0].contains("mmol") } ?? false) ? .mmolL : .mgdL

        let dataRows = rows[(headerIndex + 1)...].map { $0.map(trim) }

        // Like Clarity, Device Timestamp carries no timezone — it is the
        // reader/phone's local clock. We parse it in this device's current
        // timezone, choosing the date pattern that fits the whole document.
        let timestamps = dataRows.compactMap { fields -> String? in
            guard recordTypeCol < fields.count, Int(fields[recordTypeCol]) != nil,
                  timestampCol < fields.count, !fields[timestampCol].isEmpty else { return nil }
            return fields[timestampCol]
        }
        guard let formatter = dateFormatter(fitting: timestamps) else {
            // No decodable data rows at all; report them all as skipped.
            return CSVParseResult(rows: [], skipped: timestamps.count)
        }

        var parsed: [ParsedRow] = []
        var skipped = 0

        for fields in dataRows {
            if fields.allSatisfy(\.isEmpty) { continue }
            func field(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index]
            }
            // Rows without an integer Record Type are stray metadata.
            guard let recordType = Int(field(recordTypeCol)) else { continue }
            guard let timestamp = formatter.date(from: field(timestampCol)) else {
                skipped += 1
                continue
            }

            switch recordType {
            case 0, 1, 2:
                let valueCol = recordType == 0 ? historicCol : (recordType == 1 ? scanCol : stripCol)
                // "LO"/"HI" out-of-range placeholders fail numeric parsing and
                // are counted as skipped, like Clarity's "Low"/"High".
                guard let value = CSVImportParser.number(from: field(valueCol)) else {
                    skipped += 1
                    continue
                }
                // 0 = historic and 1 = scan both come from the sensor; 2 is a
                // blood-glucose test strip read by the meter built into the reader.
                let measurement: GlucoseMeasurementType = recordType == 2 ? .fingerstick : .cgm
                parsed.append(ParsedRow(
                    timestamp: timestamp, source: .freeStyleLibre,
                    record: .glucose(mgdL: unit.toMgdL(value), measurement: measurement, trend: nil)
                ))

            case 4:
                var decodedAny = false
                if let units = CSVImportParser.number(from: field(rapidCol)) {
                    parsed.append(ParsedRow(
                        timestamp: timestamp, source: .freeStyleLibre,
                        record: .insulin(units: units, type: .rapidActing, context: .mealBolus, name: nil)
                    ))
                    decodedAny = true
                }
                if let units = CSVImportParser.number(from: field(longCol)) {
                    parsed.append(ParsedRow(
                        timestamp: timestamp, source: .freeStyleLibre,
                        record: .insulin(units: units, type: .longActing, context: .basal, name: nil)
                    ))
                    decodedAny = true
                }
                // A "non-numeric insulin" row records that a dose happened
                // without an amount — nothing usable to import.
                if !decodedAny { skipped += 1 }

            case 5:
                guard let grams = CSVImportParser.number(from: field(carbCol)) else {
                    skipped += 1   // servings-only or "non-numeric food" rows
                    continue
                }
                // LibreView carries no meal label — infer it from the hour,
                // the same way Apple Health carbohydrate imports do.
                parsed.append(ParsedRow(
                    timestamp: timestamp, source: .freeStyleLibre,
                    record: .carbs(grams: grams,
                                   meal: MealTimeClassifier.mealType(for: timestamp),
                                   food: nil)
                ))

            default:
                skipped += 1   // ketone (3), notes (6) and other record kinds
            }
        }
        return CSVParseResult(rows: parsed, skipped: skipped)
    }

    /// Builds an `en_US_POSIX`, current-timezone formatter using the first
    /// pattern in `libreTimestampPatterns` that parses every one of
    /// `timestamps`. Falls back to the pattern that parses the most rows (the
    /// rest are then counted as skipped); `nil` when nothing parses at all.
    private static func dateFormatter(fitting timestamps: [String]) -> DateFormatter? {
        var best: (formatter: DateFormatter, parsed: Int)?
        for pattern in libreTimestampPatterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = pattern
            let parsedCount = timestamps.filter { formatter.date(from: $0) != nil }.count
            if parsedCount == timestamps.count, !timestamps.isEmpty { return formatter }
            if parsedCount > (best?.parsed ?? 0) { best = (formatter, parsedCount) }
        }
        return best?.formatter
    }

    // MARK: Helpers

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }
}
