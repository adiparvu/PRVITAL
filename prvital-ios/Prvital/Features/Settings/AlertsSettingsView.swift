import SwiftUI

/// Reactive glucose alerts: get a local notification when a fresh reading is out
/// of range. Opt-in, per-level, and driven by the thresholds set in
/// Units & targets.
struct AlertsSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var prefs = AlertPreferences.default

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var thresholds: GlucoseThresholds { env.preferences.thresholds }

    var body: some View {
        Form {
            Section {
                Toggle("Enable glucose alerts", isOn: $prefs.enabled)
            } footer: {
                Text("Get notified when a fresh reading leaves your range. Alerts use the thresholds from Units & targets and are delivered as local notifications on this device. They only fire while the app can sync a recent reading.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            if prefs.enabled {
                Section("Notify me about") {
                    alertToggle("Urgent low", "below \(value(thresholds.veryLow))", isOn: $prefs.urgentLow, tint: Theme.zoneCritical)
                    alertToggle("Low", "below \(value(thresholds.targetLower))", isOn: $prefs.low, tint: Theme.zoneWarning)
                    alertToggle("High", "above \(value(thresholds.targetUpper))", isOn: $prefs.high, tint: Theme.zoneHigh)
                    alertToggle("Very high", "above \(value(thresholds.high))", isOn: $prefs.urgentHigh, tint: Theme.zoneWarning)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Stepper(value: $prefs.snoozeMinutes, in: 5...120, step: 5) {
                        Text("Snooze repeats: \(prefs.snoozeMinutes) min")
                    }
                } footer: {
                    Text("The same level won't alert again within this window. A change in level — for example low to urgent low, or crossing back through your range — always alerts right away.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Glucose alerts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefs = env.preferences.alerts }
        .onChange(of: prefs) { oldValue, newValue in
            env.preferences.alerts = newValue
            if newValue.enabled && !oldValue.enabled {
                Task { _ = await env.notifications.requestAuthorization() }
            }
        }
    }

    private func alertToggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .tint(tint)
    }

    private func value(_ mgdL: Double) -> String {
        GlucoseFormatting.labeled(mgdL: mgdL, unit: unit)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { AlertsSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
