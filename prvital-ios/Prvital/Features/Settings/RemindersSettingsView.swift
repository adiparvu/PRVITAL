import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Reminders, rebuilt: an honest permission card that reflects the REAL system
/// state (allow / allowed / turned off in Settings), then one section per
/// reminder — each localized, each revealing its times when enabled, with
/// times addable and removable. Every change writes back immediately and
/// reschedules the local notifications. No reminder ever carries a medical
/// value.
struct RemindersSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @State private var reminders = ReminderPreferences.default
    @State private var loaded = false
    #if canImport(UserNotifications)
    @State private var authStatus: UNAuthorizationStatus?
    #endif

    /// At most this many times per reminder — enough for a full day without
    /// letting the list (and the pending-notification budget) run away.
    private static let maxTimes = 6

    var body: some View {
        Form {
            authorizationSection

            Section {
                Toggle(isOn: $reminders.journalEnabled) {
                    RemindersLabel(title: "Journal check-ins", systemImage: "book.closed", tint: Theme.accent)
                }
                .tint(Theme.accent)
                if reminders.journalEnabled {
                    editableTimeRows(\.journalTimes, labelKey: "Time %lld")
                }
            } footer: {
                Text("A gentle nudge to log how you're doing.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Toggle(isOn: $reminders.basalEnabled) {
                    RemindersLabel(title: "Basal insulin", systemImage: "syringe", tint: Theme.zoneWarning)
                }
                .tint(Theme.accent)
                if reminders.basalEnabled {
                    DatePicker("Time", selection: basalBinding, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("A daily reminder for your long-acting dose.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Toggle(isOn: $reminders.mealsEnabled) {
                    RemindersLabel(title: "Mealtimes", systemImage: "fork.knife", tint: Theme.zoneHigh)
                }
                .tint(Theme.accent)
                if reminders.mealsEnabled {
                    editableTimeRows(\.mealTimes, labelKey: "Meal %lld")
                }
            } footer: {
                Text("Remember to log carbs and any bolus.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Toggle(isOn: $reminders.glucoseCheckEnabled) {
                    RemindersLabel(title: "Glucose checks", systemImage: "drop", tint: Theme.zoneInRange)
                }
                .tint(Theme.accent)
                if reminders.glucoseCheckEnabled {
                    editableTimeRows(\.glucoseCheckTimes, labelKey: "Check %lld")
                }
            } footer: {
                Text("Keep your trend complete with a quick reading.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Toggle(isOn: $reminders.hydrationEnabled) {
                    RemindersLabel(title: "Hydration", systemImage: "waterbottle", tint: Theme.accent)
                }
                .tint(Theme.accent)
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
            .glassListRow()

            morningReportSection
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded {
                reminders = env.preferences.reminders
                loaded = true
            }
            refreshAuthorization()
        }
        .onChange(of: morningEnabled) { _, _ in env.rearmMorningReport() }
        .onChange(of: morningTime) { _, _ in env.rearmMorningReport() }
        // Coming back from the Settings app after flipping the permission —
        // re-read the real state so the card is never stale.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshAuthorization() }
        }
        .onChange(of: reminders) { _, newValue in
            env.preferences.reminders = newValue
            env.notifications.reschedule(from: newValue, glucoseSchedule: env.preferences.glucoseSchedule,
                                         medicationPlan: env.preferences.medicationPlan)
            // The wholesale clear above also drops the contextual nudges;
            // re-arm them now instead of waiting for the next data change.
            env.rescheduleContextualReminders()
        }
    }

    // MARK: Permission card

    @ViewBuilder
    private var authorizationSection: some View {
        Section {
            #if canImport(UserNotifications)
            switch authStatus {
            case .authorized, .provisional, .ephemeral:
                Label {
                    Text("Notifications allowed").foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.zoneInRange)
                }
            case .denied:
                Label {
                    Text("Notifications are off for Prvital. Turn them on in Settings.")
                        .foregroundStyle(Theme.textPrimary)
                } icon: {
                    Image(systemName: "bell.slash.fill").foregroundStyle(Theme.zoneWarning)
                }
                Button {
                    Haptics.play(.light)
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    #endif
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.forward.app")
                        .foregroundStyle(Theme.accent)
                }
            default:
                Button {
                    Haptics.play(.light)
                    Task {
                        _ = await env.notifications.requestAuthorization()
                        refreshAuthorization()
                    }
                } label: {
                    Label("Allow notifications", systemImage: "bell.badge.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            #endif
        } footer: {
            Text("Reminders are delivered by the system as local notifications. Grant permission once so scheduled reminders can appear.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    // MARK: Morning report

    /// The overnight summary lives on Preferences directly (not in the
    /// ReminderPreferences blob) because its content is data-driven and
    /// re-armed by the sync pipeline, not by the static scheduler.
    private var morningEnabled: Bool { env.preferences.morningReportEnabled }
    private var morningTime: Int { env.preferences.morningReportMinutes }

    @ViewBuilder private var morningReportSection: some View {
        @Bindable var preferences = env.preferences
        Section {
            Toggle(isOn: $preferences.morningReportEnabled) {
                RemindersLabel(title: "Morning report", systemImage: "sunrise.fill", tint: Theme.zoneWarning)
            }
            .tint(Theme.accent)
            if preferences.morningReportEnabled {
                DatePicker(
                    "Delivery time",
                    selection: Binding(
                        get: {
                            Calendar.current.startOfDay(for: Date())
                                .addingTimeInterval(TimeInterval(preferences.morningReportMinutes * 60))
                        },
                        set: { date in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                            preferences.morningReportMinutes = (comps.hour ?? 7) * 60 + (comps.minute ?? 30)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        } footer: {
            Text("A quiet note when you wake: overnight time in range, the lowest point and when. No sound, no alarm — just the night, summarised.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassListRow()
    }

    private func refreshAuthorization() {
        #if canImport(UserNotifications)
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authStatus = settings.authorizationStatus
        }
        #endif
    }

    // MARK: Time rows (add / remove)

    /// The numbered time rows for one reminder, each removable (down to one),
    /// plus an "Add time" row while under the cap.
    @ViewBuilder
    private func editableTimeRows(
        _ keyPath: WritableKeyPath<ReminderPreferences, [Int]>, labelKey: String
    ) -> some View {
        ForEach(reminders[keyPath: keyPath].indices, id: \.self) { index in
            HStack(spacing: 10) {
                DatePicker(
                    String(format: String(localized: String.LocalizationValue(labelKey)), index + 1),
                    selection: arrayTimeBinding(keyPath, index),
                    displayedComponents: .hourAndMinute
                )
                if reminders[keyPath: keyPath].count > 1 {
                    Button {
                        Haptics.play(.selection)
                        var times = reminders[keyPath: keyPath]
                        guard times.indices.contains(index) else { return }
                        times.remove(at: index)
                        reminders[keyPath: keyPath] = times
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove time")
                }
            }
        }
        if reminders[keyPath: keyPath].count < Self.maxTimes {
            Button {
                Haptics.play(.selection)
                var times = reminders[keyPath: keyPath]
                // A sensible next slot: an hour after the latest time, wrapping
                // at midnight.
                let next = ((times.max() ?? 11 * 60) + 60) % (24 * 60)
                times.append(next)
                reminders[keyPath: keyPath] = times
            } label: {
                Label("Add time", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
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
            get: {
                let times = reminders[keyPath: keyPath]
                guard times.indices.contains(index) else { return remindersDate(fromMinutes: 8 * 60) }
                return remindersDate(fromMinutes: times[index])
            },
            set: { date in
                guard reminders[keyPath: keyPath].indices.contains(index) else { return }
                reminders[keyPath: keyPath][index] = remindersMinutes(from: date)
            }
        )
    }
}

// MARK: - Private helpers

/// A titled, tinted toggle label used by every reminder section. The title is a
/// `LocalizedStringKey` — as a plain `String` it silently skipped localization
/// and the row names showed in English.
private struct RemindersLabel: View {
    let title: LocalizedStringKey
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
