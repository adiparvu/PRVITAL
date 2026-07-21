import SwiftUI
import SwiftData

/// "In plain words" — a friendly, sentence-by-sentence read-out of the user's
/// day or week, generated from the same statistics the charts use. Reads are
/// scoped to the last eight days so both periods are covered cheaply.
struct PlainLanguageSummaryView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var readings: [GlucoseReading]
    @State private var period: SummaryPeriod = .today

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -8, to: Date())
            ?? Date().addingTimeInterval(-8 * 86400)
        _readings = Query(
            filter: #Predicate<GlucoseReading> { $0.timestamp >= start },
            sort: \.timestamp, order: .reverse)
    }

    private var summary: PlainLanguageSummary {
        let now = Date()
        let cal = Calendar.current
        let start: Date = period == .today
            ? cal.startOfDay(for: now)
            : (cal.date(byAdding: .day, value: -7, to: now) ?? now)
        let scoped = readings.filter { $0.isActive && $0.timestamp >= start && $0.timestamp <= now }
        let stats = StatisticsEngine.glucose(scoped, thresholds: env.preferences.thresholds)
        return PlainLanguageSummarizer.summary(
            stats: stats, period: period,
            goalFraction: env.preferences.glucoseGoals.targetTIRFraction,
            unit: env.preferences.glucoseUnit)
    }

    private var periodBinding: Binding<SummaryPeriod> {
        Binding(get: { period }, set: { Haptics.play(.selection); period = $0 })
    }

    var body: some View {
        let summary = self.summary
        return ScrollView {
            VStack(spacing: 18) {
                Picker("Period", selection: periodBinding) {
                    Text("Today").tag(SummaryPeriod.today)
                    Text("Week").tag(SummaryPeriod.week)
                }
                .pickerStyle(.segmented)

                SectionCard(LocalizedStringKey(summary.headline), systemImage: "text.quote") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(summary.sentences.enumerated()), id: \.offset) { _, sentence in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                    .accessibilityHidden(true)
                                Text(sentence)
                                    .font(.callout)
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Generated from your own readings — a gentle read, not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
        }
        .prvitalTabBackground()
        .navigationTitle("In plain words")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { PlainLanguageSummaryView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
