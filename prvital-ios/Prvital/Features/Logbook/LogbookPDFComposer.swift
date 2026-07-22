import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Renders the Registru as a paginated A4 **landscape** PDF — the same table
/// the doctor's paper register uses, printed black on white with light
/// gridlines. Mirrors `ExportService`'s approach: `UIGraphicsPDFRenderer`,
/// `NSAttributedString` drawing, and a temporary file URL handed to the system
/// share sheet (which includes Print).
///
/// Deliberately NOT `@MainActor`: every member is pure, self-contained UIKit
/// drawing (no shared view state), and `UIGraphicsPDFRenderer.writePDF(to:)`
/// invokes its actions closure on a *nonisolated* context — a main-actor
/// composer can't call its own helpers from inside that closure under Swift 6
/// strict concurrency. The one call site (`LogbookContent`) already runs on the
/// main actor, so this stays on-main in practice while compiling cleanly.
enum LogbookPDFComposer {
    #if canImport(UIKit)

    // A4 landscape at 72 dpi.
    private static let pageSize = CGSize(width: 842, height: 595)
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 15
    private static let headerHeight: CGFloat = 24
    private static let footerReserve: CGFloat = 14
    private static let titleBlockHeight: CGFloat = 40

    // Column widths, left to right. Comments absorbs the remainder.
    private static let dateWidth: CGFloat = 62
    private static let glucoseWidth: CGFloat = 54
    private static let insulinWidth: CGFloat = 46

    private static var columnWidths: [CGFloat] {
        let content = pageSize.width - margin * 2
        let comments = content - dateWidth - glucoseWidth * 7 - insulinWidth * 3
        return [dateWidth]
            + Array(repeating: glucoseWidth, count: 7)
            + Array(repeating: insulinWidth, count: 3)
            + [comments]
    }

    private static var columnTitles: [String] {
        ["Date"]
            + LogbookGlucoseSlot.allCases.map(\.title)
            + ["Insulin breakfast", "Insulin lunch", "Insulin dinner"]
            + ["Comments"]
    }

    /// Writes the PDF to a temporary file and returns its URL.
    /// Rows are printed oldest first — the paper register reads chronologically
    /// down the page — regardless of the on-screen (newest-first) order.
    static func writePDF(
        rows: [LogbookRow],
        unit: GlucoseUnit,
        periodLabel: String,
        patientName: String?
    ) throws -> URL {
        let ordered = rows.sorted { $0.day < $1.day }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let name = "Prvital-Logbook-\(Int(Date().timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appending(path: name)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yy"

        try renderer.writePDF(to: url) { ctx in
            let maxRowBottom = pageSize.height - margin - footerReserve
            var pageNumber = 0
            var y: CGFloat = 0

            func beginPage() {
                ctx.beginPage()
                pageNumber += 1
                y = margin
                if pageNumber == 1 {
                    drawTitleBlock(unit: unit, periodLabel: periodLabel, patientName: patientName)
                    y += titleBlockHeight
                }
                drawColumnHeaders(atY: y, context: ctx.cgContext)
                y += headerHeight
                drawFooter(pageNumber: pageNumber)
            }

            beginPage()
            var pageTop = y   // first gridline row of the current page

            for row in ordered {
                if y + rowHeight > maxRowBottom {
                    drawVerticalGridlines(from: pageTop - headerHeight, to: y, context: ctx.cgContext)
                    beginPage()
                    pageTop = y
                }
                drawRow(row, atY: y, unit: unit, dateFormatter: dateFormatter, context: ctx.cgContext)
                y += rowHeight
            }
            drawVerticalGridlines(from: pageTop - headerHeight, to: y, context: ctx.cgContext)
        }
        return url
    }

    // MARK: - Blocks

    private static func drawTitleBlock(unit: GlucoseUnit, periodLabel: String, patientName: String?) {
        draw("Glucose monitoring log",
             in: CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: 20),
             font: .boldSystemFont(ofSize: 16), alignment: .left)
        let subtitle = ([patientName, periodLabel, "Glucose in \(unit.rawValue) · Insulin in units (U)"]
            .compactMap { $0 })
            .joined(separator: "   ·   ")
        draw(subtitle,
             in: CGRect(x: margin, y: margin + 22, width: pageSize.width - margin * 2, height: 12),
             font: .systemFont(ofSize: 9), color: .darkGray, alignment: .left)
    }

    private static func drawColumnHeaders(atY y: CGFloat, context: CGContext) {
        var x = margin
        for (title, width) in zip(columnTitles, columnWidths) {
            draw(title,
                 in: CGRect(x: x + 1, y: y + 2, width: width - 2, height: headerHeight - 4),
                 font: .systemFont(ofSize: 6.5, weight: .semibold),
                 lineBreakMode: .byWordWrapping)
            x += width
        }
        // A slightly stronger rule under the header.
        strokeLine(from: CGPoint(x: margin, y: y + headerHeight),
                   to: CGPoint(x: pageSize.width - margin, y: y + headerHeight),
                   width: 0.8, context: context)
    }

    private static func drawRow(
        _ row: LogbookRow,
        atY y: CGFloat,
        unit: GlucoseUnit,
        dateFormatter: DateFormatter,
        context: CGContext
    ) {
        var values: [String] = [dateFormatter.string(from: row.day)]
        for slot in LogbookGlucoseSlot.allCases {
            let cell = row.cell(for: slot)
            values.append(cell.mgdL.map { GlucoseFormatting.string(mgdL: $0, unit: unit) } ?? "—")
        }
        for column in row.insulinColumns {
            values.append(column.units.map { $0.formatted() } ?? "—")
        }
        values.append(row.comment.isEmpty ? "—" : row.comment)

        var x = margin
        for (index, (value, width)) in zip(values, columnWidths).enumerated() {
            let isComments = index == values.count - 1
            draw(value,
                 in: CGRect(x: x + 2, y: y + 3.5, width: width - 4, height: rowHeight - 4),
                 font: .systemFont(ofSize: isComments ? 6.5 : 8),
                 alignment: isComments ? .left : .center)
            x += width
        }
        strokeLine(from: CGPoint(x: margin, y: y + rowHeight),
                   to: CGPoint(x: pageSize.width - margin, y: y + rowHeight),
                   width: 0.4, context: context)
    }

    private static func drawVerticalGridlines(from top: CGFloat, to bottom: CGFloat, context: CGContext) {
        var x = margin
        for width in columnWidths {
            strokeLine(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: bottom), width: 0.4, context: context)
            x += width
        }
        strokeLine(from: CGPoint(x: x, y: top), to: CGPoint(x: x, y: bottom), width: 0.4, context: context)
        strokeLine(from: CGPoint(x: margin, y: top), to: CGPoint(x: pageSize.width - margin, y: top),
                   width: 0.8, context: context)
    }

    private static func drawFooter(pageNumber: Int) {
        let dateText = Date().formatted(date: .abbreviated, time: .shortened)
        let y = pageSize.height - margin - footerReserve + 4
        draw("Generated by Prvital · \(dateText)",
             in: CGRect(x: margin, y: y, width: 300, height: 10),
             font: .systemFont(ofSize: 7), color: .gray, alignment: .left)
        draw("Page \(pageNumber)",
             in: CGRect(x: pageSize.width - margin - 60, y: y, width: 60, height: 10),
             font: .systemFont(ofSize: 7), color: .gray, alignment: .right)
    }

    // MARK: - Primitives

    private static func draw(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor = .black,
        alignment: NSTextAlignment = .center,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(with: rect,
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attrs, context: nil)
    }

    private static func strokeLine(from: CGPoint, to: CGPoint, width: CGFloat, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(UIColor(white: 0.75, alpha: 1).cgColor)
        context.setLineWidth(width)
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
        context.restoreGState()
    }

    #else

    static func writePDF(
        rows: [LogbookRow],
        unit: GlucoseUnit,
        periodLabel: String,
        patientName: String?
    ) throws -> URL {
        throw CocoaError(.featureUnsupported)
    }

    #endif
}
