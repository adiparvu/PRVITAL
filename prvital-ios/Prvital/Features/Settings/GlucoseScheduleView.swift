import SwiftUI

/// Lets the user design their own glucose-logging routine: the times of day they
/// want to check, with friendly labels, and whether to be reminded. Changes are
/// saved live and reschedule the local reminders.
struct GlucoseScheduleView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var schedule = GlucoseSchedule.default
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Toggle("Remind me to log", isOn: $schedule.remindersEnabled.animation())
            } footer: {
                Text("Get a gentle local notification at each enabled time. Prvital never sends your data anywhere — reminders are scheduled on this device.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach($schedule.slots) { $slot in
                    slotRow($slot)
                }
                .onDelete { schedule.slots.remove(atOffsets: $0) }

                Button {
                    addSlot()
                } label: {
                    Label("Add a time", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Your logging times")
            } footer: {
                Text("For example: a waking reading at 07:00, one before each meal, and one at bedtime. Swipe a time to remove it.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Logging schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onAppear {
            guard !loaded else { return }
            schedule = env.preferences.glucoseSchedule
            loaded = true
        }
        .onChange(of: schedule) { oldValue, newValue in
            env.preferences.glucoseSchedule = newValue
            env.notifications.reschedule(from: env.preferences.reminders, glucoseSchedule: newValue)
            if newValue.remindersEnabled, !oldValue.remindersEnabled {
                Task { _ = await env.notifications.requestAuthorization() }
            }
        }
    }

    private func slotRow(_ slot: Binding<GlucoseLogSlot>) -> some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Label", text: slot.label)
                    .font(.body.weight(.medium))
                Spacer()
                Toggle("", isOn: slot.enabled).labelsHidden()
            }
            DatePicker("Time", selection: timeBinding(slot), displayedComponents: .hourAndMinute)
                .disabled(!slot.wrappedValue.enabled)
                .opacity(slot.wrappedValue.enabled ? 1 : 0.5)
        }
        .padding(.vertical, 2)
    }

    private func timeBinding(_ slot: Binding<GlucoseLogSlot>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: slot.wrappedValue.hour,
                    minute: slot.wrappedValue.minute,
                    second: 0, of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                slot.wrappedValue.minutesFromMidnight = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    private func addSlot() {
        Haptics.play(.selection)
        withAnimation(.snappy) {
            schedule.slots.append(GlucoseLogSlot(label: "New time", minutesFromMidnight: 12 * 60))
        }
    }
}

#Preview {
    NavigationStack { GlucoseScheduleView() }
        .environment(AppEnvironment.preview())
}
