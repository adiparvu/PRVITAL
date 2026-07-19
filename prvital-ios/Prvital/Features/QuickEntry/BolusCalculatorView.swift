import SwiftUI
import SwiftData

/// The opt-in **bolus calculator**: a transparent helper that shows insulin on
/// board and a suggested dose broken into its carb, correction and IOB parts.
///
/// It never doses anything on its own — the suggestion is only a starting point,
/// and logging is a separate, explicit tap the user makes after reviewing it.
struct BolusCalculatorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \InsulinDose.timestamp, order: .reverse) private var doses: [InsulinDose]
    @Query(sort: \GlucoseReading.timestamp, order: .reverse) private var readings: [GlucoseReading]
    @Query(sort: \CarbEntry.timestamp, order: .reverse) private var carbEntries: [CarbEntry]

    @State private var carbs: Double = 0
    @State private var glucoseDisplay: Double = 0
    @State private var didLoad = false

    private var params: BolusParameters { env.preferences.bolusParameters }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }
    private var unit: GlucoseUnit { env.preferences.glucoseUnit }

    private var recentDoses: [InsulinDose] {
        let cutoff = Date().addingTimeInterval(-params.durationHours * 3600)
        return doses.filter { $0.timestamp >= cutoff }
    }
    private var iob: Double {
        InsulinMath.activeInsulin(doses: recentDoses, at: Date(), parameters: params)
    }
    private var cob: Double {
        CarbMath.carbsOnBoard(entries: carbEntries, at: Date())
    }
    private var currentMgdL: Double? {
        glucoseDisplay > 0 ? unit.toMgdL(glucoseDisplay) : nil
    }
    private var estimate: BolusEstimate {
        InsulinMath.suggestBolus(carbs: carbs, currentMgdL: currentMgdL,
                                 activeInsulin: iob, parameters: params, thresholds: thresholds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                disclaimer

                SectionCard("Inputs", systemImage: "square.and.pencil") {
                    inputRow("Carbohydrates", value: $carbs, suffix: "g", digits: 0)
                    Divider().overlay(Theme.hairline)
                    inputRow("Current glucose", value: $glucoseDisplay, suffix: unit.rawValue, digits: unit.fractionDigits)
                }

                onBoardContext

                resultCard

                if !estimate.warnings.isEmpty {
                    SectionCard("Check first", systemImage: "exclamationmark.triangle.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(estimate.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }

                logButton
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Bolus calculator")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadOnce)
    }

    // MARK: Sections

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cross.case.fill")
                .foregroundStyle(Theme.accent)
            Text("A calculator, not a prescription. It uses only your saved ratios and is not medical advice. Always confirm with your own judgement and care team before dosing.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.accentSoft, in: .rect(cornerRadius: 14))
    }

    private var onBoardContext: some View {
        SectionCard("On board", systemImage: "chart.line.downtrend.xyaxis") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 22) {
                    labeledValue("\(iob.formatted(.number.precision(.fractionLength(1)))) U", "Insulin")
                    labeledValue("\(cob.formatted(.number.precision(.fractionLength(0)))) g", "Carbs")
                    Spacer()
                }
                Text(cob > 0
                     ? "Insulin on board is already subtracted below. Active carbs from earlier meals are shown for context and are not added to the dose — factor them into your own judgement."
                     : "Insulin on board is already subtracted from the suggestion below.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func labeledValue(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var resultCard: some View {
        SectionCard("Suggested dose", systemImage: "syringe") {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(estimate.suggested.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text("U")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 6) {
                    breakdownRow("Carbs", estimate.carbBolus, sign: "+")
                    breakdownRow("Correction", estimate.correctionBolus, sign: estimate.correctionBolus < 0 ? "−" : "+", magnitude: abs(estimate.correctionBolus))
                    breakdownRow("Insulin on board", estimate.activeInsulin, sign: "−")
                }
            }
        }
    }

    private var logButton: some View {
        Button {
            log()
        } label: {
            Text("Log \(estimate.suggested.formatted(.number.precision(.fractionLength(0...1)))) U")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .disabled(estimate.suggested <= 0)
    }

    // MARK: Rows

    private func inputRow(_ title: String, value: Binding<Double>, suffix: String, digits: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...max(0, digits))))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(suffix).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func breakdownRow(_ title: String, _ value: Double, sign: String, magnitude: Double? = nil) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(sign)\((magnitude ?? value).formatted(.number.precision(.fractionLength(1)))) U")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: Actions

    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        if let latest = readings.first(where: \.isActive) {
            glucoseDisplay = unit.fromMgdL(latest.valueMgdL)
        }
    }

    private func log() {
        let units = estimate.suggested
        guard units > 0 else { return }
        Haptics.play(.success)
        env.entryStore.addInsulin(units: units, type: .rapidActing, context: .mealBolus,
                                  note: "From bolus calculator")
        dismiss()
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { BolusCalculatorView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
