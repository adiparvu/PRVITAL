import SwiftUI

/// The Analize heatmap: average glucose by weekday × time-of-day, each cell
/// tinted by its zone, so a glance shows which windows run high or low. Columns
/// follow the locale's first weekday; empty buckets stay faint.
struct GlucoseHeatmapCard: View {
    let heatmap: GlucoseHeatmap
    let unit: GlucoseUnit
    let thresholds: GlucoseThresholds

    private var calendar: Calendar { .current }

    /// Column order honouring the locale's first weekday (0 = Sunday … 6 = Saturday).
    private var columns: [Int] {
        let first = (calendar.firstWeekday - 1) % 7
        return (0..<7).map { (first + $0) % 7 }
    }

    var body: some View {
        SectionCard("Glucose heatmap", systemImage: "square.grid.3x3.fill") {
            if !heatmap.hasData {
                EmptyStateView(systemImage: "square.grid.3x3", title: "No data",
                               message: "Average by day and time.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    grid
                    legend
                    Text("Average by day and time.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 26, height: 10)
                ForEach(columns, id: \.self) { col in
                    Text(weekdaySymbol(col))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<heatmap.blocksPerDay, id: \.self) { block in
                GridRow {
                    Text(blockLabel(block))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 26, alignment: .trailing)
                    ForEach(columns, id: \.self) { col in
                        cell(value(block, col))
                    }
                }
            }
        }
    }

    private func value(_ block: Int, _ col: Int) -> Double? {
        guard block < heatmap.averages.count, col < heatmap.averages[block].count else { return nil }
        return heatmap.averages[block][col]
    }

    private func cell(_ avg: Double?) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(avg.map { thresholds.zone(forMgdL: $0).color } ?? Theme.hairline.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .overlay {
                if let avg {
                    Text(GlucoseFormatting.string(mgdL: avg, unit: unit))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .accessibilityLabel(avg.map { GlucoseFormatting.labeled(mgdL: $0, unit: unit) } ?? "")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(Theme.zoneCritical, "Below")
            legendDot(Theme.zoneInRange, "In range")
            legendDot(Theme.zoneHigh, "Above")
            Spacer()
        }
    }

    private func legendDot(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func weekdaySymbol(_ col: Int) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return col < symbols.count ? symbols[col] : ""
    }

    private func blockLabel(_ block: Int) -> String {
        let hours = max(1, 24 / heatmap.blocksPerDay)
        return "\(block * hours)"
    }
}
