import SwiftUI

/// Sick-day guidance for people with diabetes. Static, widely-taught education —
/// never medical advice and never an insulin dose. It gathers the standard
/// sick-day rules (keep taking insulin, check more often, watch for ketones, stay
/// hydrated, know when to call for help) and lets the user turn on a lightweight
/// "sick-day mode" that surfaces a reminder banner on the dashboard.
struct SickDayView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header.appearTransition(delay: 0)
                modeCard.appearTransition(delay: 0.04)
                rulesCard.appearTransition(delay: 0.10)
                whenToCallCard.appearTransition(delay: 0.16)
                disclaimer.appearTransition(delay: 0.22)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Sick-day mode")
        .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        SickDayView()
            .environment(env)
            .modelContainer(env.modelContainer)
    }
}
