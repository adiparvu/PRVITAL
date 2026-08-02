import SwiftUI
import SwiftData

/// Sick-day guidance for people with diabetes. Static, widely-taught education —
/// never medical advice and never an insulin dose. It gathers the standard
/// sick-day rules (keep taking insulin, check more often, watch for ketones, stay
/// hydrated, know when to call for help), lets the user log ketone readings, and
/// lets them turn on a lightweight "sick-day mode" that surfaces a reminder
/// banner on the dashboard.
struct SickDayView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: \KetoneReading.timestamp, order: .reverse) private var ketones: [KetoneReading]
    @State private var showingLogKetone = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header.appearTransition(delay: 0)
                modeCard.appearTransition(delay: 0.04)
                ketonesCard.appearTransition(delay: 0.08)
                rulesCard.appearTransition(delay: 0.12)
                whenToCallCard.appearTransition(delay: 0.18)
                disclaimer.appearTransition(delay: 0.24)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Sick-day mode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLogKetone) { LogKetoneSheet() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.zoneWarning)
                .frame(width: 56, height: 56)
                .background(Theme.zoneWarning.opacity(0.14), in: .circle)
            Text("Illness, infection and stress can push glucose up (or sometimes down) and change how much insulin you need. These are the standard rules for staying safe while you're unwell.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var modeCard: some View {
        @Bindable var prefs = env.preferences
        return SectionCard("Sick-day mode", systemImage: "bandage.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Turn on while you're unwell", isOn: $prefs.sickDayEnabled)
                    .tint(Theme.accent)
                Text("Shows a sick-day reminder on your dashboard so this guidance is one tap away. Turn it off when you're feeling better.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if prefs.sickDayEnabled, let started = prefs.sickDayStartedAt {
                    Label("On since \(started.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Stamp / clear the start time as the switch flips, and refresh the
        // contextual reminders so the tighter sick-day check cadence applies now.
        .onChange(of: prefs.sickDayEnabled) { _, isOn in
            prefs.sickDayStartedAt = isOn ? Date() : nil
            env.rescheduleContextualReminders()
        }
    }

    // MARK: - Ketones

    /// Records ketone readings and shows the latest one with its risk band and
    /// supportive guidance. Ketones are the early sign of DKA, so they live right
    /// under the sick-day toggle.
    private var ketonesCard: some View {
        let latest = ketones.first
        let logButton = AnyView(
            Button {
                Haptics.play(.selection)
                showingLogKetone = true
            } label: {
                Label("Log ketones", systemImage: "plus.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityHint("Record a blood or urine ketone reading.")
        )
        return SectionCard("Ketones", systemImage: "drop.triangle.fill", accessory: logButton) {
            VStack(alignment: .leading, spacing: 12) {
                if let latest {
                    let band = KetoneBands.band(forMmolPerL: latest.value)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(latest.value.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(ketoneTint(band))
                            .monospacedDigit()
                        Text("mmol/L")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        bandChip(band)
                    }
                    Text(band.guidance)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(latest.sample.label) · \(latest.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    Text("No ketone readings yet. If you have strips, checking when glucose runs high or you feel unwell is a good habit.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bandChip(_ band: KetoneBand) -> some View {
        Text(band.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(ketoneTint(band))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ketoneTint(band).opacity(0.14), in: Capsule())
    }

    private func ketoneTint(_ band: KetoneBand) -> Color {
        switch band.severity {
        case 0: return Theme.zoneInRange
        case 1: return Theme.zoneWarning
        case 2: return Theme.zoneHigh
        default: return Theme.zoneCritical
        }
    }

    private var rulesCard: some View {
        SectionCard("The sick-day rules", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 16) {
                sickDayRule(
                    icon: "syringe.fill",
                    title: "Keep taking your insulin",
                    body: "Never stop your basal (background) insulin, even if you can't eat — your body still needs it, and stopping it when ill can lead to ketones and DKA. Your team may adjust doses; ask them, don't skip."
                )
                Divider().overlay(Theme.hairline)
                sickDayRule(
                    icon: "clock.arrow.circlepath",
                    title: "Check glucose more often",
                    body: "Test roughly every 2–4 hours, including overnight, because illness can move your numbers quickly."
                )
                Divider().overlay(Theme.hairline)
                sickDayRule(
                    icon: "drop.triangle.fill",
                    title: "Check ketones when high",
                    body: "If you have ketone strips and your glucose is high (for example above 240 mg/dL / 13.3 mmol/L), or you feel unwell, check for ketones and follow your team's ketone plan."
                )
                Divider().overlay(Theme.hairline)
                sickDayRule(
                    icon: "waterbottle.fill",
                    title: "Stay hydrated",
                    body: "Sip plenty of sugar-free fluids to avoid dehydration. If you can't eat your usual meals, switch to carb-containing drinks (like regular juice or soda) to keep some carbs going in."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var whenToCallCard: some View {
        SectionCard("When to get help", systemImage: "phone.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Contact your care team or seek urgent care if you have:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                warningRow("Persistent vomiting or diarrhoea, or you can't keep fluids down")
                warningRow("Moderate or high ketones, or ketones that keep rising")
                warningRow("Glucose that stays high, or lows you can't bring up")
                warningRow("Trouble breathing, drowsiness, confusion, or belly pain")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sickDayRule(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func warningRow(_ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.zoneCritical)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("This is general guidance — follow your care team's plan and your own sick-day rules. Seek urgent help if symptoms are severe.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// A compact dashboard banner shown while sick-day mode is on. Taps through to the
/// full guidance. Mirrors the sensor banner's style so it sits naturally in the
/// dashboard's card stack.
struct SickDayBanner: View {
    var body: some View {
        NavigationLink {
            SickDayView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cross.case.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.zoneWarning)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sick-day mode is on")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Keep taking insulin, check more often, watch for ketones, stay hydrated.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens sick-day guidance")
    }
}

/// Shown on the dashboard when glucose has been running high for a sustained
/// stretch and sick-day mode is *off* — a gentle nudge to check ketones and take
/// precautions. Taps through to the full guidance. Never alarming.
struct SickDaySuggestionBanner: View {
    let averageMgdL: Double
    let unit: GlucoseUnit

    var body: some View {
        NavigationLink {
            SickDayView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.zoneHigh)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Running high for a while")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Around \(GlucoseFormatting.labeled(mgdL: averageMgdL, unit: unit)) lately. Checking ketones and reviewing sick-day steps can help.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens sick-day guidance and ketone logging")
    }
}

/// A sheet for recording a blood or urine ketone reading (mmol/L), with the risk
/// band shown live as the value changes.
struct LogKetoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Nil until typed — the field opens empty (gray "0" placeholder) instead of
    // holding a real zero the user has to delete first.
    @State private var value: Double?
    @State private var sample: KetoneSample = .blood
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Just the box — you type the reading (device feedback:
                    // no stepper).
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("0", value: $value, format: .number)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .keyboardType(.decimalPad)
                            .fixedSize()
                            .accessibilityLabel("Ketone reading")
                        Text("mmol/L").foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .onChange(of: value) { _, newValue in
                        guard let newValue else { return }
                        if newValue < 0 { value = 0 } else if newValue > 8 { value = 8 }
                    }
                    Picker("Sample", selection: $sample) {
                        ForEach(KetoneSample.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let value, value >= KetoneBands.elevatedThreshold {
                        Text(KetoneBands.band(forMmolPerL: value).guidance)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Ketone reading")
                } footer: {
                    Text("Blood ketones are measured in mmol/L. Urine strips read differently — record the number your meter or strip shows.")
                }
                Section {
                    DatePicker("Time", selection: $date, in: ...Date())
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log ketones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // A typed 0 is a real reading ("no ketones") and stays
                    // savable; only an untouched empty field is not.
                    Button("Save", action: save).disabled(value == nil)
                }
            }
        }
    }

    private func save() {
        let reading = KetoneReading(
            value: value ?? 0, sample: sample, timestamp: date,
            note: note.isEmpty ? nil : note)
        modelContext.insert(reading)
        try? modelContext.save()
        Haptics.play(.success)
        dismiss()
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        SickDayView()
            .environment(env)
            .modelContainer(env.modelContainer)
    }
}
