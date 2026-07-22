import SwiftUI
import SwiftData

/// Export — assembles an `ExportInput` for the chosen interval and writes a PDF
/// or CSV report **locally** through `env.exporter`, then offers the file via a
/// `ShareLink`. Nothing leaves the device unless the user taps share. Failures
/// surface in a simple alert.
struct ExportView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var glucose: [GlucoseReading]
    @Query private var insulin: [InsulinDose]
    @Query private var carbs: [CarbEntry]
    @Query private var activity: [ActivityEntry]
    @Query private var observations: [ObservationEntry]

    init() {
        // Export offers up to a year; cap at ~400 days. (Full-history CSV import
        // is a separate path that streams the file, not this screen.)
        let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: Date())
            ?? Date().addingTimeInterval(-400 * 86_400)
        _glucose = Query(filter: #Predicate<GlucoseReading> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _insulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff },
                         sort: \.timestamp, order: .reverse)
        _carbs = Query(filter: #Predicate<CarbEntry> { $0.timestamp >= cutoff },
                       sort: \.timestamp, order: .reverse)
        _activity = Query(filter: #Predicate<ActivityEntry> { $0.startTimestamp >= cutoff },
                          sort: \.startTimestamp, order: .reverse)
        _observations = Query(filter: #Predicate<ObservationEntry> { $0.timestamp >= cutoff },
                              sort: \.timestamp, order: .reverse)
    }

    @State private var interval: InsightsInterval = .month
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isExporting = false

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
                if let url = exportedURL { shareCard(url).appearTransition() }
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
                    export(.pdf)
                } label: {
                    exportLabel("Export PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button {
                    export(.csv)
                } label: {
                    exportLabel("Export CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            .disabled(recordCount == 0 || isExporting)
            .opacity(recordCount == 0 ? 0.5 : 1)
        }
    }

    /// A generate button's label, swapping the icon for a spinner while writing.
    private func exportLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            if isExporting { ProgressView() } else { Image(systemName: systemImage) }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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

    private enum ExportFormat { case pdf, csv }

    /// Generates the report for the chosen format, storing the URL on success or
    /// surfacing an alert. Yields once first so the button's spinner paints
    /// before the (synchronous, main-actor) report generation runs.
    private func export(_ format: ExportFormat) {
        isExporting = true
        Task { @MainActor in
            await Task.yield()
            do {
                let input = makeInput()
                let url: URL
                switch format {
                case .pdf: url = try env.exporter.writePDF(input)
                case .csv: url = try env.exporter.writeCSV(input)
                }
                exportedURL = url
                Haptics.play(.success)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
                Haptics.play(.warning)
            }
            isExporting = false
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
