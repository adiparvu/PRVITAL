import SwiftUI
import StoreKit

/// Settings hub. A grouped list of destinations for sources, units, reminders,
/// privacy, data controls and the audit trail. Two rows surface live state as
/// subtitles — the current glucose unit and the chosen primary source — so the
/// most important choices are visible without drilling in.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.requestReview) private var requestReview
    @State private var showWhatsNew = false
    @State private var showFeedback = false
    @State private var achievementStore = AchievementStore()

    private var medicationsSubtitle: String {
        let count = env.preferences.medicationPlan.activeSchedules.count
        switch count {
        case 0: return String(localized: "Track pills & injectables")
        case 1: return String(localized: "1 medication")
        default: return String(localized: "\(count) medications")
        }
    }

    private var achievementsSubtitle: String {
        let unseen = achievementStore.unseenCount
        if unseen > 0 { return String(localized: "\(unseen) new to unlock") }
        let earned = achievementStore.earned.count
        return earned > 0
            ? String(localized: "\(earned) earned")
            : String(localized: "Track your milestones")
    }

    private var scheduleSubtitle: String {
        let count = env.preferences.glucoseSchedule.activeSlots.count
        let times = count == 1
            ? String(localized: "\(count) time a day")
            : String(localized: "\(count) times a day")
        return env.preferences.glucoseSchedule.remindersEnabled
            ? String(localized: "\(times) · reminders on")
            : times
    }

    var body: some View {
        let unit = env.preferences.glucoseUnit
        let primary = env.registry.primarySource

        let profile = env.profile.current()

        return NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileView(profile: profile)
                    } label: {
                        ProfileSettingsRow(profile: profile)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        UnitsSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Units & targets",
                            subtitle: unit.rawValue,
                            systemImage: "ruler",
                            tint: Theme.zoneInRange
                        )
                    }

                    NavigationLink {
                        AlertsHubView()
                    } label: {
                        SettingsRow(
                            title: "Glucose alerts",
                            subtitle: env.preferences.alerts.anyCategoryEnabled ? String(localized: "On") : String(localized: "Off"),
                            systemImage: "exclamationmark.triangle.fill",
                            tint: Theme.zoneCritical
                        )
                    }

                    NavigationLink {
                        GlucoseScheduleView()
                    } label: {
                        SettingsRow(
                            title: "Logging schedule",
                            subtitle: scheduleSubtitle,
                            systemImage: "clock.badge.checkmark",
                            tint: Theme.accent
                        )
                    }

                    NavigationLink {
                        TherapySettingsView()
                    } label: {
                        SettingsRow(
                            title: "Therapy & bolus",
                            subtitle: env.preferences.bolusParameters.isEnabled
                                ? String(localized: "Calculator on")
                                : String(localized: "Calculator off"),
                            systemImage: "syringe",
                            tint: Theme.zoneWarning
                        )
                    }

                    NavigationLink {
                        MedicationsView()
                    } label: {
                        SettingsRow(
                            title: "Medications",
                            subtitle: medicationsSubtitle,
                            systemImage: "pills.fill",
                            tint: Theme.accent
                        )
                    }
                } header: {
                    Text("Glucose & therapy")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        SourcesSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Sources",
                            subtitle: String(localized: "Primary: \(primary.displayName)"),
                            systemImage: primary.symbol,
                            tint: Theme.accent
                        )
                    }

                    NavigationLink {
                        SensorView()
                    } label: {
                        SettingsRow(
                            title: "Sensor",
                            subtitle: String(localized: "Warm-up & expiry countdown"),
                            systemImage: "sensor.tag.radiowaves.forward",
                            tint: Theme.zoneInRange
                        )
                    }

                    NavigationLink {
                        EmergencyCardView()
                    } label: {
                        SettingsRow(
                            title: "Emergency card",
                            subtitle: env.preferences.emergencyInfo.hasContent
                                ? String(localized: "Ready to show a helper")
                                : String(localized: "Not set up yet"),
                            systemImage: "staroflife.fill",
                            tint: Theme.zoneCritical
                        )
                    }
                } header: {
                    Text("Devices & safety")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        RemindersSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Reminders",
                            subtitle: String(localized: "Local, on-device notifications"),
                            systemImage: "bell.badge",
                            tint: Theme.zoneHigh
                        )
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Appearance",
                            subtitle: (AccentTheme(rawValue: env.preferences.accentThemeRaw) ?? .default).displayName,
                            systemImage: "paintpalette.fill",
                            tint: Theme.accent
                        )
                    }
                } header: {
                    Text("App")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        PrivacyDashboardView()
                    } label: {
                        SettingsRow(
                            title: "Privacy",
                            subtitle: String(localized: "Consent & permissions"),
                            systemImage: "hand.raised.fill",
                            tint: Theme.accent
                        )
                    }

                    NavigationLink {
                        SharingView()
                    } label: {
                        SettingsRow(
                            title: "Sharing",
                            subtitle: String(localized: "Partner, caregiver & care team"),
                            systemImage: "person.2.fill",
                            tint: Theme.zoneInRange
                        )
                    }

                    NavigationLink {
                        DataControlsView()
                    } label: {
                        SettingsRow(
                            title: "Data & control",
                            subtitle: String(localized: "Sync, delete, export"),
                            systemImage: "externaldrive.fill",
                            tint: Theme.zoneWarning
                        )
                    }

                    NavigationLink {
                        AuditLogView()
                    } label: {
                        SettingsRow(
                            title: "Audit trail",
                            subtitle: String(localized: "A log of every sensitive action"),
                            systemImage: "list.bullet.rectangle.portrait",
                            tint: Theme.textSecondary
                        )
                    }
                } header: {
                    Text("Data & privacy")
                } footer: {
                    Text("Prvital is private by design. Your health data lives on this device (and, only if you turn it on, your own private iCloud). It is never sold, never used for advertising, and never used to train models without your consent.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        SettingsRow(
                            title: "Achievements",
                            subtitle: achievementsSubtitle,
                            systemImage: "rosette",
                            tint: Theme.zoneHigh
                        )
                    }
                    Button {
                        showWhatsNew = true
                    } label: {
                        SettingsRow(
                            title: "What's new",
                            subtitle: String(localized: "A tour of Prvital's best features"),
                            systemImage: "sparkles",
                            tint: Theme.accent
                        )
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button {
                        Haptics.play(.light)
                        showFeedback = true
                    } label: {
                        SettingsRow(
                            title: "Send feedback",
                            subtitle: String(localized: "Ideas, problems or a kind word"),
                            systemImage: "envelope",
                            tint: Theme.accent
                        )
                    }
                    Button {
                        Haptics.play(.selection)
                        requestReview()
                    } label: {
                        SettingsRow(
                            title: "Rate Prvital",
                            subtitle: String(localized: "A rating helps others find us"),
                            systemImage: "star",
                            tint: Theme.zoneHigh
                        )
                    }
                } header: {
                    Text("Help & feedback")
                } footer: {
                    Text("Prvital \(AppInfo.versionBuild)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .prvitalTabBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showWhatsNew) { WhatsNewView() }
            .sheet(isPresented: $showFeedback) { FeedbackView() }
        }
    }
}

// MARK: - Private helpers

/// The profile row at the top of Settings: a larger, card-like avatar and name
/// (per device feedback: make the profile block bigger). The medical summary
/// stays inside the profile, not on the settings list. The avatar shows the
/// user's photo when set, otherwise their initials on the ring colour.
private struct ProfileSettingsRow: View {
    @Bindable var profile: UserProfile

    private var ring: Color {
        profile.avatarColorValue.map { Color(hex: $0) } ?? Theme.accent
    }

    var body: some View {
        HStack(spacing: 16) {
            AvatarView(
                imageData: profile.avatarImageData,
                initials: profile.initials,
                symbol: profile.avatarSymbol,
                tint: ring,
                ring: ring,
                diameter: 60
            )

            Text(profile.displayName.isEmpty ? "Your profile" : profile.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.displayName.isEmpty ? Text("Your profile") : Text(profile.displayName))
    }
}

/// A settings destination row: a tinted glyph, a title and a live subtitle.
private struct SettingsRow: View {
    /// Localized row title. `subtitle` shows live data (a unit, a source name).
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        // Combine the (localized) title and the subtitle for VoiceOver.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return SettingsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
