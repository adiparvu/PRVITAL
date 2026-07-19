import SwiftUI

/// Settings hub. A grouped list of destinations for sources, units, reminders,
/// privacy, data controls and the audit trail. Two rows surface live state as
/// subtitles — the current glucose unit and the chosen primary source — so the
/// most important choices are visible without drilling in.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let unit = env.preferences.glucoseUnit
        let primary = env.registry.primarySource

        return NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SourcesSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Sources",
                            subtitle: "Primary: \(primary.displayName)",
                            systemImage: primary.symbol,
                            tint: Theme.accent
                        )
                    }

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
                        RemindersSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Reminders",
                            subtitle: "Local, on-device notifications",
                            systemImage: "bell.badge",
                            tint: Theme.zoneHigh
                        )
                    }

                    NavigationLink {
                        AlertsSettingsView()
                    } label: {
                        SettingsRow(
                            title: "Glucose alerts",
                            subtitle: env.preferences.alerts.enabled ? "On" : "Off",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: Theme.zoneCritical
                        )
                    }

                    NavigationLink {
                        TherapySettingsView()
                    } label: {
                        SettingsRow(
                            title: "Therapy & bolus",
                            subtitle: env.preferences.bolusParameters.isEnabled ? "Calculator on" : "Calculator off",
                            systemImage: "syringe",
                            tint: Theme.zoneWarning
                        )
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        PrivacyDashboardView()
                    } label: {
                        SettingsRow(
                            title: "Privacy",
                            subtitle: "Consent & permissions",
                            systemImage: "hand.raised.fill",
                            tint: Theme.accent
                        )
                    }

                    NavigationLink {
                        DataControlsView()
                    } label: {
                        SettingsRow(
                            title: "Data & control",
                            subtitle: "Sync, delete, export",
                            systemImage: "externaldrive.fill",
                            tint: Theme.zoneWarning
                        )
                    }

                    NavigationLink {
                        AuditLogView()
                    } label: {
                        SettingsRow(
                            title: "Audit trail",
                            subtitle: "A log of every sensitive action",
                            systemImage: "list.bullet.rectangle.portrait",
                            tint: Theme.textSecondary
                        )
                    }
                } footer: {
                    Text("Prvital is private by design. Your health data lives on this device (and, only if you turn it on, your own private iCloud). It is never sold, never used for advertising, and never used to train models without your consent.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Private helpers

/// A settings destination row: a tinted glyph, a title and a live subtitle.
private struct SettingsRow: View {
    let title: String
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return SettingsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
