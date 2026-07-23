import SwiftUI
import Charts

/// Apple-Health-style detail for a single wellness metric: a Day / Week / Month /
/// Year picker over a chart, with the period's headline figures. Data comes
/// bucketed from `HealthKitService.metricSeries` (hourly for a day, daily for a
/// week or month, monthly for a year), loaded off the main thread; the view only
/// renders the prepared series.
struct MetricDetailView: View {
    @Environment(AppEnvironment.self) private var env

    let kind: HealthMetricKind
    let title: LocalizedStringKey
    let systemImage: String
    let unit: String
    let color: Color
    let cumulative: Bool

    @State private var interval: MetricInterval = .week
    @State private var series: MetricSeries = .empty
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Period", selection: $interval) {
                    Text("Day").tag(MetricInterval.day)
                    Text("Week").tag(MetricInterval.week)
                    Text("Month").tag(MetricInterval.month)
                    Text("Year").tag(MetricInterval.year)
                }
                .pickerStyle(.segmented)

                summaryRow
                chartCard
            }
            .padding()
        }
        .prvitalScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: interval) {
            loading = true
            series = await env.healthKit.metricSeries(kind, interval: interval)
            loading = false
        }
    }

    // MARK: Summary

    private var summaryRow: some View {
        HStack(spacing: 12) {
            if cumulative {
                stat("Total", total)
                stat("Average", series.average)
            } else {
                stat("Average", series.average)
                stat("Minimum", series.minimum)
                stat("Maximum", series.maximum)
            }
        }
        .opacity(series.isEmpty ? 0.4 : 1)
    }

    private var total: Double { series.points.reduce(0) { $0 + $1.value } }

    private func stat(_ label: LocalizedStringKey, _ value: Double) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(format(value)).font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(GlassListRowBackground().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func format(_ v: Double) -> String {
        let digits = cumulative ? 0 : (abs(v) < 10 ? 1 : 0)
        return v.formatted(.number.precision(.fractionLength(digits)))
    }

    // MARK: Chart

    @ViewBuilder private var chartCard: some View {
        SectionCard(title, systemImage: systemImage) {
            if series.isEmpty {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    EmptyStateView(systemImage: "heart.text.square",
                                   title: "No data",
                                   message: "No data for this period.")
                }
            } else {
                Chart(series.points) { point in
                    if cumulative {
                        BarMark(x: .value("Time", point.day, unit: barUnit),
                                y: .value("Value", point.value))
                            .foregroundStyle(color.gradient)
                            .cornerRadius(3)
                    } else {
                        LineMark(x: .value("Time", point.day),
                                 y: .value("Value", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        AreaMark(x: .value("Time", point.day),
                                 y: .value("Value", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(color.opacity(0.12).gradient)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: cumulative))
                .frame(height: 220)
            }
        }
    }

    private var barUnit: Calendar.Component {
        switch interval {
        case .day: return .hour
        case .week, .month: return .day
        case .year: return .month
        }
    }
}
