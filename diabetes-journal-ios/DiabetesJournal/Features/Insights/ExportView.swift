import SwiftUI
import SwiftData

/// Export — assembles an `ExportInput` for the chosen interval and writes a PDF
/// or CSV report **locally** through `env.exporter`, then offers the file via a
/// `ShareLink`. Nothing leaves the device unless the user taps share. Failures
/// surface in a simple alert.
struct ExportView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var glucose: [GlucoseReading]
    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var insulin: [InsulinDose]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbs: [CarbEntry]
    @Query(sort: \ActivityEntry.startTimestamp, order: .reverse) private var activity: [ActivityEntry]
    @Query(sort: \ObservationEntry.timestamp, order: .reverse) private var observations: [ObservationEntry]

    @State private var interval: InsightsInterval = .month
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showingError = false

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var range: ClosedRange<Date> { interval.dateRange() }

    // MARK: Filtered data

    private var activeReadings: [GlucoseReading] {
        glucose.filter { $0.isActive && range.contains($0.timestamp) }
    }
    private var filteredInsulin: [InsulinDose] {
        insulin.filter { range.contains($0.timestamp) }
    }
    private var filteredCarbs: [CarbEntry] {
        carbs.filter { range.contains($0.timestamp) }
    }
    private var filteredActivity: [ActivityEntry] {
        activity.filter { range.contains($0.startTimestamp) }
    }
    private var filteredObservations: [ObservationEntry] {
        observations.filter { range.contains($0.timestamp) }
    }

    private var recordCount: Int {
        activeReadings.count + filteredInsulin.count + filteredCarbs.count
            + filteredActivity.count + filteredObservations.count
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                intervalCard
                contentsCard
                actionsCard
                if let url = exportedURL { shareCard(url) }
                warningCard
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: interval) { _, _ in exportedURL = nil }
        .alert("Export failed", isPresented: $showingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Cards

    private var intervalCard: some View {
        SectionCard("Period", systemImage: "calendar") {
            Picker("Interval", selection: $interval) {
                ForEach(InsightsInterval.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var contentsCard: some View {
        SectionCard("Included", systemImage: "doc.text.magnifyingglass") {
            VStack(spacing: 8) {
                contentRow("drop.fill", "Glucose readings", activeReadings.count, Theme.accent)
                contentRow("syringe.fill", "Insulin doses", filteredInsulin.count, Theme.accent)
                contentRow("fork.knife", "Meals", filteredCarbs.count, Theme.zoneHigh)
                contentRow("figure.walk", "Activities", filteredActivity.count, Theme.zoneInRange)
                contentRow("note.text", "Observations", filteredObservations.count, Theme.textSecondary)
            }
        }
    }

    private func contentRow(_ symbol: String, _ title: String, _ count: Int, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(tint).frame(width: 22)
            Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(count)")
    }

    private var actionsCard: some View {
        SectionCard("Generate report", systemImage: "square.and.arrow.up") {
            VStack(spacing: 12) {
                Text(interval.periodLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    export { try env.exporter.writePDF(makeInput()) }
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button {
                    export { try env.exporter.writeCSV(makeInput()) }
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            .disabled(recordCount == 0)
            .opacity(recordCount == 0 ? 0.5 : 1)
        }
    }

    private func shareCard(_ url: URL) -> some View {
        SectionCard("Ready to share", systemImage: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(url.lastPathComponent)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ShareLink(item: url) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.zoneInRange)
            }
        }
    }

    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(Theme.zoneWarning)
            Text("This report contains sensitive health data. It is generated on "
                 + "your device and never leaves it unless you choose to share it. "
                 + "Share only with people you trust, such as your care team, and "
                 + "delete copies you no longer need.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Export plumbing

    private func makeInput() -> ExportInput {
        let base = StatisticsEngine.glucose(activeReadings, thresholds: thresholds)
        let stats = StatisticsEngine.enrich(
            base,
            insulin: filteredInsulin,
            carbs: filteredCarbs,
            activity: filteredActivity
        )
        return ExportInput(
            periodLabel: interval.periodLabel,
            glucose: activeReadings,
            insulin: filteredInsulin,
            carbs: filteredCarbs,
            activity: filteredActivity,
            observations: filteredObservations,
            statistics: stats,
            unit: unit,
            thresholds: thresholds
        )
    }

    /// Runs a throwing writer, storing the URL on success or surfacing an alert.
    private func export(_ writer: () throws -> URL) {
        do {
            let url = try writer()
            exportedURL = url
            Haptics.play(.success)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            Haptics.play(.warning)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        ExportView()
            .environment(env)
            .modelContainer(env.modelContainer)
    }
}
