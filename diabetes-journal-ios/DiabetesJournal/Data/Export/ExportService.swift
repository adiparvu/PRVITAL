import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The data an export summarises. Assembled by the statistics/history stores.
struct ExportInput {
    var periodLabel: String
    var glucose: [GlucoseReading]
    var insulin: [InsulinDose]
    var carbs: [CarbEntry]
    var activity: [ActivityEntry]
    var observations: [ObservationEntry]
    var statistics: PeriodStatistics
    var unit: GlucoseUnit
    var thresholds: GlucoseThresholds
}

/// Generates PDF and CSV reports **locally**, writing them to a temporary file
/// for the system share sheet. Both formats carry a sensitivity notice, and no
/// data leaves the device except through the share action the user takes.
@MainActor
final class ExportService {
    private let audit: AuditService?
    init(audit: AuditService? = nil) { self.audit = audit }

    static let sensitivityNotice =
        "This document contains sensitive personal health information. "
        + "Share it only with people you trust, such as your care team, and "
        + "delete copies you no longer need."

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: CSV

    func csv(_ input: ExportInput) -> String {
        var rows: [String] = []
        rows.append("record_type,timestamp_utc,source,value,unit,detail")

        for g in input.glucose.sorted(by: { $0.timestamp < $1.timestamp }) {
            let value = GlucoseFormatting.string(mgdL: g.valueMgdL, unit: input.unit)
            let detail = [g.measurementType.label, g.trend?.label].compactMap { $0 }.joined(separator: " · ")
            rows.append(line("glucose", g.timestamp, g.source, value, input.unit.rawValue, detail))
        }
        for i in input.insulin.sorted(by: { $0.timestamp < $1.timestamp }) {
            let detail = [i.insulinType.label, i.doseContext.label, i.insulinName].compactMap { $0 }.joined(separator: " · ")
            rows.append(line("insulin", i.timestamp, i.source, i.units.formatted(), "U", detail))
        }
        for c in input.carbs.sorted(by: { $0.timestamp < $1.timestamp }) {
            let detail = [c.mealType.label, c.foodDescription].compactMap { $0 }.joined(separator: " · ")
            rows.append(line("carbohydrate", c.timestamp, c.source, c.grams.formatted(), "g", detail))
        }
        for a in input.activity.sorted(by: { $0.startTimestamp < $1.startTimestamp }) {
            let detail = "\(a.activityType.label) · \(a.intensity.label)"
            rows.append(line("activity", a.startTimestamp, a.source, "\(a.durationMinutes)", "min", detail))
        }
        for o in input.observations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let detail = (o.tags.map(\.label) + [o.text].compactMap { $0 }).joined(separator: " · ")
            rows.append(line("observation", o.timestamp, o.source, "", "", detail))
        }
        rows.append("")
        rows.append("# \(Self.sensitivityNotice)")
        return rows.joined(separator: "\n")
    }

    func writeCSV(_ input: ExportInput) throws -> URL {
        let url = temporaryURL(extension: "csv")
        try csv(input).data(using: .utf8)?.write(to: url, options: [.completeFileProtection])
        audit?.log(.export, userConfirmation: true, detail: "CSV · \(input.periodLabel)")
        return url
    }

    private func line(_ type: String, _ date: Date, _ source: DataSource, _ value: String, _ unit: String, _ detail: String) -> String {
        [type, iso.string(from: date), source.displayName, value, unit, detail]
            .map(escape).joined(separator: ",")
    }

    private func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func temporaryURL(extension ext: String) -> URL {
        let name = "DiabetesJournal-\(Int(Date().timeIntervalSince1970)).\(ext)"
        return FileManager.default.temporaryDirectory.appending(path: name)
    }

    // MARK: PDF

    #if canImport(UIKit)
    func writePDF(_ input: ExportInput) throws -> URL {
        let pageSize = CGSize(width: 612, height: 792) // US Letter, 72 dpi
        let margin: CGFloat = 44
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let url = temporaryURL(extension: "pdf")

        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = margin
            let width = pageSize.width - margin * 2

            y = draw("Diabetes Journal", at: y, margin: margin, width: width, font: .boldSystemFont(ofSize: 24))
            y = draw(input.periodLabel, at: y + 2, margin: margin, width: width, font: .systemFont(ofSize: 13), color: .secondaryLabel)
            y += 12

            y = draw("Summary", at: y, margin: margin, width: width, font: .boldSystemFont(ofSize: 16))
            for row in summaryRows(input) {
                y = draw(row, at: y + 2, margin: margin, width: width, font: .systemFont(ofSize: 12))
            }
            y += 14

            y = draw("Recent glucose", at: y, margin: margin, width: width, font: .boldSystemFont(ofSize: 16))
            let recent = input.glucose.sorted { $0.timestamp > $1.timestamp }.prefix(40)
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
            for g in recent {
                if y > pageSize.height - margin - 40 { ctx.beginPage(); y = margin }
                let zone = input.thresholds.zone(forMgdL: g.valueMgdL).label
                let value = GlucoseFormatting.labeled(mgdL: g.valueMgdL, unit: input.unit)
                let row = "\(df.string(from: g.timestamp))   \(value)   \(zone)   \(g.source.displayName)"
                y = draw(row, at: y + 2, margin: margin, width: width, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
            }

            // Sensitivity notice at the foot of the page.
            let notice = Self.sensitivityNotice
            _ = draw(notice, at: pageSize.height - margin - 28, margin: margin, width: width,
                     font: .italicSystemFont(ofSize: 9), color: .secondaryLabel)
        }
        audit?.log(.export, userConfirmation: true, detail: "PDF · \(input.periodLabel)")
        return url
    }

    private func summaryRows(_ input: ExportInput) -> [String] {
        let s = input.statistics
        let pct: (Double) -> String = { ($0 * 100).formatted(.number.precision(.fractionLength(0))) + "%" }
        return [
            "Average glucose: \(GlucoseFormatting.labeled(mgdL: s.average, unit: input.unit))   (GMI ≈ \(s.glucoseManagementIndicator.formatted(.number.precision(.fractionLength(1))))%)",
            "Range: \(GlucoseFormatting.labeled(mgdL: s.minimum, unit: input.unit)) – \(GlucoseFormatting.labeled(mgdL: s.maximum, unit: input.unit))",
            "Time in range: \(pct(s.timeInRange))   ·   Above: \(pct(s.timeAboveRange))   ·   Below: \(pct(s.timeBelowRange))",
            "Hypo events: \(s.hypoEvents)   ·   Hyper events: \(s.hyperEvents)",
            "Insulin — bolus: \(s.totalBolusUnits.formatted()) U · basal: \(s.totalBasalUnits.formatted()) U",
            "Carbs: \(s.totalCarbGrams.formatted()) g across \(s.mealCount) meal(s)   ·   Activity: \(s.activityMinutes) min",
        ]
    }

    @discardableResult
    private func draw(_ text: String, at y: CGFloat, margin: CGFloat, width: CGFloat, font: UIFont, color: UIColor = .label) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil)
        (text as NSString).draw(with: CGRect(x: margin, y: y, width: width, height: bounding.height),
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attrs, context: nil)
        return y + bounding.height
    }
    #endif
}
