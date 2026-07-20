import SwiftUI

/// Reminders. Edits a working copy of the user's `ReminderPreferences` — daily
/// journal / basal / meal / glucose-check times plus a hydration interval — and
/// on every change writes it back and reschedules the local notifications. No
/// reminder ever carries a medical value.
struct RemindersSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var reminders = ReminderPreferences.default
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Button {
                    Haptics.play(.light)
                    Task { _ = await env.notifications.requestAuthorization() }
                } label: {
                    Label("Allow notifications", systemImage: "bell.badge.fill")
                        .foregroundStyle(Theme.accent)
                }
            } footer: {
                Text("Reminders are delivered by the system as local notifications. Grant permission once so scheduled reminders can appear.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle(isOn: $reminders.journalEnabled) {
                    RemindersLabel(title: "Journal check-ins", systemImage: "book.closed", tint: Theme.accent)
                }
                if reminders.journalEnabled {
                    ForEach(reminders.journalTimes.indices, id: \.self) { index in
                        DatePicker(
                            "Time \(index + 1)",
                            selection: arrayTimeBinding(\.journalTimes, index),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            } footer: {
                Text("A gentle nudge to log how you're doing.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle(isOn: $reminders.basalEnabled) {
                    RemindersLabel(title: "Basal insulin", systemImage: "syringe", tint: Theme.zoneWarning)
                }
                if reminders.basalEnabled {
                    DatePicker("Time", selection: basalBinding, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("A daily reminder for your long-acting dose.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle(isOn: $reminders.mealsEnabled) {
                    RemindersLabel(title: "Mealtimes", systemImage: "fork.knife", tint: Theme.zoneHigh)
                }
                if reminders.mealsEnabled {
                    ForEach(reminders.mealTimes.indices, id: \.self) { index in
                        DatePicker(
                            "Meal \(index + 1)",
                            selection: arrayTimeBinding(\.mealTimes, index),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            } footer: {
                Text("Remember to log carbs and any bolus.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle(isOn: $reminders.glucoseCheckEnabled) {
                    RemindersLabel(title: "Glucose checks", systemImage: "drop", tint: Theme.zoneInRange)
                }
                if reminders.glucoseCheckEnabled {
                    ForEach(reminders.glucoseCheckTimes.indices, id: \.self) { index in
                        DatePicker(
                            "Check \(index + 1)",
                            selection: arrayTimeBinding(\.glucoseCheckTimes, index),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            } footer: {
                Text("Keep your trend complete with a quick reading.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle(isOn: $reminders.hydrationEnabled) {
                    RemindersLabel(title: "Hydration", systemImage: "waterbottle", tint: Theme.accent)
                }
                if reminders.hydrationEnabled {
                    Stepper(value: $reminders.hydrationIntervalHours, in: 1...12) {
                        HStack {
                            Text("Every").foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(reminders.hydrationIntervalHours) h")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .contentTransition(.numericText())
                        }
                    }
                    .accessibilityValue("Every \(reminders.hydrationIntervalHours) hours")
                }
            } footer: {
                Text("A repeating reminder to drink water through the day.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            reminders = env.preferences.reminders
            loaded = true
        }
        .onChange(of: reminders) { _, newValue in
            env.preferences.reminders = newValue
            env.notifications.reschedule(from: newValue, glucoseSchedule: env.preferences.glucoseSchedule)
        }
    }

    // MARK: Bindings

    private var basalBinding: Binding<Date> {
        Binding(
            get: { remindersDate(fromMinutes: reminders.basalTime) },
            set: { reminders.basalTime = remindersMinutes(from: $0) }
        )
    }

    private func arrayTimeBinding(_ keyPath: WritableKeyPath<ReminderPreferences, [Int]>, _ index: Int) -> Binding<Date> {
        Binding(
            get: { remindersDate(fromMinutes: reminders[keyPath: keyPath][index]) },
            set: { reminders[keyPath: keyPath][index] = remindersMinutes(from: $0) }
        )
    }
}

// MARK: - Private helpers

/// A titled, tinted toggle label used by every reminder section.
private struct RemindersLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title).foregroundStyle(Theme.textPrimary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }
}

/// Converts minutes-from-midnight into a `Date` on today for a `DatePicker`.
private func remindersDate(fromMinutes minutes: Int) -> Date {
    let clamped = max(0, min(minutes, 24 * 60 - 1))
    let start = Calendar.current.startOfDay(for: Date())
    return Calendar.current.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: start) ?? start
}

/// Converts a `DatePicker` `Date` back into minutes-from-midnight.
private func remindersMinutes(from date: Date) -> Int {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { RemindersSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
