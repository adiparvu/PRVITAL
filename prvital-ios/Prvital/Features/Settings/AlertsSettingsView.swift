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
        @Bindable var preferences = env.preferences
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

                if prefs.urgentLow {
                    Section {
                        Toggle("Repeat until acknowledged", isOn: $preferences.criticalAlarm.escalationEnabled)
                            .tint(Theme.zoneCritical)
                        if preferences.criticalAlarm.escalationEnabled {
                            Picker("Repeat every", selection: $preferences.criticalAlarm.repeatMinutes) {
                                Text("3 minutes").tag(3)
                                Text("5 minutes").tag(5)
                                Text("10 minutes").tag(10)
                            }
                            Picker("Max repeats", selection: $preferences.criticalAlarm.maxRepeats) {
                                Text("3").tag(3)
                                Text("6").tag(6)
                                Text("10").tag(10)
                            }
                        }
                    } header: {
                        Text("Urgent low escalation")
                    } footer: {
                        Text("When an urgent low alert isn't acknowledged, it repeats on this schedule until you tap the alert or its \"I'm on it\" button, until a newer synced reading shows you back at or above the urgent-low threshold, or until the maximum number of repeats. Standing down automatically relies on the app syncing a newer reading. In Focus or silent mode, delivery follows the system's Time Sensitive notification rules.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Stepper(value: $prefs.snoozeMinutes, in: 5...120, step: 5) {
                        Text("Snooze repeats: \(prefs.snoozeMinutes) min")
                            .contentTransition(.numericText())
                            .animation(.snappy, value: prefs.snoozeMinutes)
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
        .animation(.easeInOut(duration: 0.25), value: prefs.enabled)
        .animation(.easeInOut(duration: 0.25), value: env.preferences.criticalAlarm.escalationEnabled)
        .navigationTitle("Glucose alerts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefs = env.preferences.alerts }
        .onChange(of: prefs) { oldValue, newValue in
            env.preferences.alerts = newValue
            if newValue.enabled && !oldValue.enabled {
                Task { _ = await env.notifications.requestAuthorization() }
            }
            // Silencing urgent-low alerts (or all alerts) also stands down any
            // armed critical-low repeats.
            if (oldValue.enabled && !newValue.enabled) || (oldValue.urgentLow && !newValue.urgentLow) {
                CriticalAlarmScheduler.standDown()
            }
        }
        .onChange(of: env.preferences.criticalAlarm.escalationEnabled) { wasOn, isOn in
            if isOn {
                // Registers the "I'm on it" category and (re)requests permission.
                Task { _ = await env.notifications.requestAuthorization() }
            } else if wasOn {
                // Turning escalation off cancels any repeats already scheduled.
                CriticalAlarmScheduler.standDown()
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
