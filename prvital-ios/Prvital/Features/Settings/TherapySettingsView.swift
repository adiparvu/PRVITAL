import SwiftUI

/// Therapy settings for the opt-in **bolus calculator**: the user's own ratios
/// and insulin-action timing. Nothing here is suggested by the app — the values
/// come from the user's care plan — and the calculator stays hidden until the
/// switch is on and the numbers are valid.
struct TherapySettingsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var params = BolusParameters.default

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var perUnit: String { "\(unit.rawValue)/U" }

    var body: some View {
        Form {
            Section {
                Toggle("Enable bolus calculator", isOn: $params.isEnabled)
            } footer: {
                Text("A calculator to help you think through a dose — never a prescription. It uses only the numbers you enter below and is not a substitute for your clinician's advice. Always double-check before dosing.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            if params.isEnabled {
                Section("Ratios") {
                    numberRow("Carb ratio", value: $params.carbRatio, suffix: "g/U", digits: 1)
                    numberRow("Correction factor", value: isfBinding, suffix: perUnit, digits: unit.fractionDigits)
                    numberRow("Target glucose", value: targetBinding, suffix: unit.rawValue, digits: unit.fractionDigits)
                }
                .listRowBackground(Theme.surface)

                Section {
                    numberRow("Insulin duration", value: $params.durationHours, suffix: "h", digits: 1)
                    numberRow("Time to peak", value: $params.peakMinutes, suffix: "min", digits: 0)
                    numberRow("Max bolus", value: $params.maxBolus, suffix: "U", digits: 0)
                } header: {
                    Text("Insulin action")
                } footer: {
                    Text("Duration and time-to-peak shape the insulin-on-board curve. Typical rapid-acting values are 4–6 hours and 60–90 minutes. The max bolus is a safety limit — a suggestion above it is clamped.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                if params.isValid {
                    Section {
                        NavigationLink {
                            BolusCalculatorView()
                        } label: {
                            Label("Open bolus calculator", systemImage: "syringe")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    Section {
                        Label("Enter positive ratios, and a time-to-peak shorter than half the duration, to use the calculator.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.zoneWarning)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Therapy & bolus")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { params = env.preferences.bolusParameters }
        .onChange(of: params) { _, newValue in
            env.preferences.bolusParameters = newValue
        }
    }

    // MARK: Fields

    private func numberRow(_ title: String, value: Binding<Double>, suffix: String, digits: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...max(0, digits))))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(suffix)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Correction factor is a mg/dL delta per unit; convert for the chosen unit.
    private var isfBinding: Binding<Double> {
        Binding(
            get: { unit.fromMgdL(params.correctionFactor) },
            set: { params.correctionFactor = unit.toMgdL($0) }
        )
    }

    private var targetBinding: Binding<Double> {
        Binding(
            get: { unit.fromMgdL(params.targetMgdL) },
            set: { params.targetMgdL = unit.toMgdL($0) }
        )
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { TherapySettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
