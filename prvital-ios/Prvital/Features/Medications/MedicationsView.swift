import SwiftUI
import SwiftData

/// Medications — a plan of the user's non-insulin meds with a daily take-checklist,
/// a 7-day adherence read-out, and the schedule editor. Logged doses are real
/// records (they flow into the journal); the plan itself lives in Preferences.
struct MedicationsView: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var recentDoses: [MedicationDose]
    @State private var editing: MedicationSchedule?

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -8, to: Date())
            ?? Date().addingTimeInterval(-8 * 86400)
        _recentDoses = Query(
            filter: #Predicate<MedicationDose> { $0.timestamp >= start },
            sort: \.timestamp, order: .reverse)
    }

    private var plan: MedicationPlan { env.preferences.medicationPlan }

    var body: some View {
        let plan = self.plan
        let slots = MedicationAdherence.todaySlots(plan: plan, doses: recentDoses)

        return Form {
            if !slots.isEmpty {
                Section {
                    ForEach(slots) { slot in
                        MedicationSlotRow(slot: slot) { logDose(scheduleID: slot.scheduleID) }
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text("Tap Take when you've had a dose. It's logged to your journal.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)
            }

            if !plan.activeSchedules.isEmpty {
                Section {
                    adherenceCard
                } header: {
                    Text("Adherence · last 7 days")
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                ForEach(plan.schedules) { schedule in
                    Button { editing = schedule } label: { MedicationRow(schedule: schedule) }
                }
                Button {
                    Haptics.play(.selection)
                    editing = MedicationSchedule(times: [8 * 60])
                } label: {
                    Label("Add a medication", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text("My medications")
            } footer: {
                Text("Add the pills or injectables you take, with the times you take them. Prvital can remind you and track how consistently you've taken them. This is a personal log, not medical advice.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { schedule in
            MedicationEditorSheet(
                schedule: schedule,
                isExisting: plan.schedules.contains { $0.id == schedule.id },
                onSave: save, onDelete: delete)
        }
    }

    private var adherenceCard: some View {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let summary = MedicationAdherence.summary(plan: plan, doses: recentDoses, start: start)
        let pct = Int((summary.fraction * 100).rounded())
        return HStack(spacing: 16) {
            GaugeRing(fraction: summary.fraction, label: "\(pct)%")
            VStack(alignment: .leading, spacing: 4) {
                Text("\(summary.taken) of \(summary.expected) doses taken")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(adherenceEncouragement(summary.fraction))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adherence \(pct) percent, \(summary.taken) of \(summary.expected) doses")
    }

    private func adherenceEncouragement(_ f: Double) -> String {
        switch f {
        case 0.9...: return String(localized: "Excellent consistency — keep it up.")
        case 0.7..<0.9: return String(localized: "Good going. A little more consistency helps.")
        default: return String(localized: "Reminders can help you stay on track.")
        }
    }

    // MARK: Actions

    private func logDose(scheduleID: UUID) {
        guard let s = plan.schedules.first(where: { $0.id == scheduleID }) else { return }
        Haptics.play(.success)
        env.entryStore.addMedication(
            name: s.name, kind: s.kind, amount: s.amount,
            unitText: s.unitText, scheduleID: s.id.uuidString)
    }

    private func save(_ schedule: MedicationSchedule) {
        var p = env.preferences.medicationPlan
        if let i = p.schedules.firstIndex(where: { $0.id == schedule.id }) {
            p.schedules[i] = schedule
        } else {
            p.schedules.append(schedule)
        }
        env.preferences.medicationPlan = p
        rescheduleReminders()
    }

    private func delete(_ schedule: MedicationSchedule) {
        var p = env.preferences.medicationPlan
        p.schedules.removeAll { $0.id == schedule.id }
        env.preferences.medicationPlan = p
        rescheduleReminders()
    }

    private func rescheduleReminders() {
        if env.preferences.medicationPlan.hasReminders {
            Task { _ = await env.notifications.requestAuthorization() }
        }
        env.notifications.reschedule(
            from: env.preferences.reminders,
            glucoseSchedule: env.preferences.glucoseSchedule,
            medicationPlan: env.preferences.medicationPlan)
    }
}

// MARK: - Rows

private struct MedicationSlotRow: View {
    let slot: MedicationSlot
    let onTake: () -> Void

    private var timeText: String {
        var c = DateComponents(); c.hour = slot.minute / 60; c.minute = slot.minute % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: slot.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(slot.taken ? Theme.zoneInRange : Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.name).font(.body).foregroundStyle(Theme.textPrimary)
                Text("\(slot.doseText) · \(timeText)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if slot.taken {
                Label("Taken", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Theme.zoneInRange)
                    .accessibilityLabel("Taken")
            } else {
                Button("Take", action: onTake)
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.name), \(slot.doseText), \(timeText), \(slot.taken ? String(localized: "taken") : String(localized: "not taken"))")
    }
}

private struct MedicationRow: View {
    let schedule: MedicationSchedule

    private var timesText: String {
        guard !schedule.times.isEmpty else { return String(localized: "No times set") }
        return schedule.sortedTimes.map { m -> String in
            var c = DateComponents(); c.hour = m / 60; c.minute = m % 60
            let d = Calendar.current.date(from: c) ?? Date()
            return d.formatted(date: .omitted, time: .shortened)
        }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(schedule.enabled ? Theme.accent : Theme.textTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.name.isEmpty ? String(localized: "Untitled") : schedule.name)
                    .font(.body).foregroundStyle(Theme.textPrimary)
                Text("\(schedule.doseText) · \(timesText)")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if !schedule.enabled {
                Text("Off").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            } else if schedule.remindersEnabled {
                Image(systemName: "bell.fill").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 2)
    }
}

/// A small adherence ring reused for the medication summary.
private struct GaugeRing: View {
    let fraction: Double
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Theme.accent.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 62, height: 62)
        .accessibilityHidden(true)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { MedicationsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
