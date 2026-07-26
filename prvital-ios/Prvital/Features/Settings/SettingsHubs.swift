import SwiftUI

/// The Prvio-style settings hubs: instead of one long list, Settings shows a
/// handful of big hub rows, and each hub opens one of these focused screens —
/// exactly how Prvio's "Casa mea" sub-menu works. Every row is monochrome
/// (colour stays reserved for semantics), on the dark-glass Prvio surface.

// MARK: - Glucose & therapy

struct GlucoseTherapyHubView: View {
    @Environment(AppEnvironment.self) private var env

    private var medicationsSubtitle: String {
        let count = env.preferences.medicationPlan.activeSchedules.count
        switch count {
        case 0: return String(localized: "Track pills & injectables")
        case 1: return String(localized: "1 medication")
        default: return String(localized: "\(count) medications")
        }
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
        List {
            Section {
                NavigationLink {
                    UnitsSettingsView()
                } label: {
                    PrvioRow(title: "Units & targets",
                             subtitle: env.preferences.glucoseUnit.rawValue,
                             systemImage: "ruler")
                }
                NavigationLink {
                    AlertsHubView()
                } label: {
                    PrvioRow(title: "Glucose alerts",
                             subtitle: env.preferences.alerts.anyCategoryEnabled
                                ? String(localized: "On") : String(localized: "Off"),
                             systemImage: "exclamationmark.triangle")
                }
                NavigationLink {
                    GlucoseScheduleView()
                } label: {
                    PrvioRow(title: "Logging schedule",
                             subtitle: scheduleSubtitle,
                             systemImage: "clock.badge.checkmark")
                }
                NavigationLink {
                    TherapySettingsView()
                } label: {
                    PrvioRow(title: "Therapy & bolus",
                             subtitle: env.preferences.bolusParameters.isEnabled
                                ? String(localized: "Calculator on")
                                : String(localized: "Calculator off"),
                             systemImage: "syringe")
                }
                NavigationLink {
                    MedicationsView()
                } label: {
                    PrvioRow(title: "Medications",
                             subtitle: medicationsSubtitle,
                             systemImage: "pills")
                }
            }
            .prvioListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalTabBackground()
        .navigationTitle("Glucose & therapy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - App

struct AppSettingsHubView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RemindersSettingsView()
                } label: {
                    PrvioRow(title: "Reminders",
                             subtitle: String(localized: "Local, on-device notifications"),
                             systemImage: "bell.badge")
                }
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    PrvioRow(title: "Appearance",
                             subtitle: (AccentTheme(rawValue: env.preferences.accentThemeRaw) ?? .default).displayName,
                             systemImage: "paintpalette")
                }
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    PrvioRow(title: "Language",
                             subtitle: LanguageSettingsView.currentDisplayName,
                             systemImage: "globe")
                }
            }
            .prvioListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalTabBackground()
        .navigationTitle("App")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data & privacy

struct DataPrivacyHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PrivacyDashboardView()
                } label: {
                    PrvioRow(title: "Privacy",
                             subtitle: String(localized: "Consent & permissions"),
                             systemImage: "hand.raised")
                }
                NavigationLink {
                    SharingView()
                } label: {
                    PrvioRow(title: "Sharing",
                             subtitle: String(localized: "Partner, caregiver & care team"),
                             systemImage: "person.2")
                }
                NavigationLink {
                    DataControlsView()
                } label: {
                    PrvioRow(title: "Data & control",
                             subtitle: String(localized: "Sync, delete, export"),
                             systemImage: "externaldrive")
                }
                NavigationLink {
                    AuditLogView()
                } label: {
                    PrvioRow(title: "Audit trail",
                             subtitle: String(localized: "A log of every sensitive action"),
                             systemImage: "list.bullet.rectangle.portrait")
                }
            } footer: {
                Text("Prvital is private by design. Your health data lives on this device (and, only if you turn it on, your own private iCloud). It is never sold, never used for advertising, and never used to train models without your consent.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            .prvioListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalTabBackground()
        .navigationTitle("Data & privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
