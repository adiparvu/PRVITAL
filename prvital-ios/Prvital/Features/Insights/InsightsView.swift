import SwiftUI

/// Insights — the analytics home. A segmented control flips between the visual
/// `ChartsView` and the numeric `StatisticsView`, while the toolbar offers a
/// push to `ExportView` (share a report) and to the full `HistoryView` ledger.
///
/// Both child screens share the same time-window vocabulary via
/// `InsightsInterval`, which is declared here so every Insights file can use it.
struct InsightsView: View {
    @State private var section: InsightsSection = .charts

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $section) {
                    ForEach(InsightsSection.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .onChange(of: section) { _, _ in Haptics.play(.selection) }

                switch section {
                case .charts: ChartsView()
                case .statistics: StatisticsView()
                case .agp: AGPReportView()
                }
            }
            .background(Theme.background)
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExportView()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export a report")
                }
            }
        }
    }
}

/// The two panes of the Insights screen.
private enum InsightsSection: String, CaseIterable, Identifiable {
    case charts, statistics, agp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .charts: return "Charts"
        case .statistics: return "Statistics"
        case .agp: return "AGP"
        }
    }
}

/// The shared time window used across every Insights screen. Each case yields a
/// closed date range ending *now* and starting one interval earlier — the domain
/// the charts, statistics and exports all filter to.
enum InsightsInterval: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    /// A human phrase for the window, used as the export period label.
    var periodLabel: String {
        switch self {
        case .day: return "Last 24 hours"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .year: return "Last 12 months"
        }
    }

    /// A closed range `[start, now]` where `start` is `now` minus one interval.
    func dateRange(now: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let start: Date
        switch self {
        case .day:   start = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .week:  start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .year:  start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
        return min(start, now)...now
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return InsightsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
