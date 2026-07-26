import SwiftUI
import StoreKit

/// Settings hub, in the Prvio menu language (ported at the user's request):
/// the profile card up top, a live summary card (source + sensor), a row of
/// quick chips (emergency / report / what's new), then a handful of big hub
/// rows instead of one long list — each hub opening its own focused screen.
/// Every surface is dark translucent glass the wallpaper shows through, and
/// icons are monochrome except where the meaning demands colour.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.requestReview) private var requestReview
    @State private var showWhatsNew = false
    @State private var showFeedback = false
    @State private var achievementStore = AchievementStore()

    private var achievementsSubtitle: String {
        let unseen = achievementStore.unseenCount
        if unseen > 0 { return String(localized: "\(unseen) new to unlock") }
        let earned = achievementStore.earned.count
        return earned > 0
            ? String(localized: "\(earned) earned")
            : String(localized: "Track your milestones")
    }

    var body: some View {
        let primary = env.registry.primarySource
        let profile = env.profile.current()

        return NavigationStack {
            List {
                // Profile — the Prvio anchor card.
                Section {
                    NavigationLink {
                        ProfileView(profile: profile)
                    } label: {
                        ProfileSettingsRow(profile: profile)
                    }
                }
                .prvioListRow()

                // Live summary — the "property / account" card: where the data
                // comes from, and the sensor countdown.
                Section {
                    NavigationLink {
                        SourcesSettingsView()
                    } label: {
                        PrvioRow(title: "Sources",
                                 subtitle: String(localized: "Primary: \(primary.displayName)"),
                                 systemImage: primary.symbol)
                    }
                    NavigationLink {
                        SensorView()
                    } label: {
                        PrvioRow(title: "Sensor",
                                 subtitle: String(localized: "Warm-up & expiry countdown"),
                                 systemImage: "sensor.tag.radiowaves.forward")
                    }
                }
                .prvioListRow()

                // Quick chips — Prvio's Documents / Finance / Inventory row,
                // recast as the three things worth one tap from anywhere.
                Section {
                    HStack(spacing: 10) {
                        NavigationLink {
                            EmergencyCardView()
                        } label: {
                            PrvioChipLabel(systemImage: "staroflife.fill",
                                           title: "Emergency",
                                           tint: Theme.zoneCritical)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ExportView()
                        } label: {
                            PrvioChipLabel(systemImage: "doc.text",
                                           title: "Report",
                                           tint: Theme.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.play(.light)
                            showWhatsNew = true
                        } label: {
                            PrvioChipLabel(systemImage: "sparkles",
                                           title: "What's new",
                                           tint: Theme.zoneHigh)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }

                // The hubs — a few chunky rows instead of fifteen thin ones.
                Section {
                    NavigationLink {
                        GlucoseTherapyHubView()
                    } label: {
                        PrvioRow(title: "Glucose & therapy", systemImage: "drop")
                    }
                    NavigationLink {
                        AppSettingsHubView()
                    } label: {
                        PrvioRow(title: "App", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        DataPrivacyHubView()
                    } label: {
                        PrvioRow(title: "Data & privacy", systemImage: "lock.shield")
                    }
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        PrvioRow(title: "Achievements",
                                 subtitle: achievementsSubtitle,
                                 systemImage: "rosette")
                    }
                }
                .prvioListRow()

                Section {
                    Button {
                        Haptics.play(.light)
                        showFeedback = true
                    } label: {
                        PrvioRow(title: "Send feedback",
                                 subtitle: String(localized: "Ideas, problems or a kind word"),
                                 systemImage: "envelope")
                    }
                    Button {
                        Haptics.play(.selection)
                        requestReview()
                    } label: {
                        PrvioRow(title: "Rate Prvital",
                                 subtitle: String(localized: "A rating helps others find us"),
                                 systemImage: "star")
                    }
                } header: {
                    Text("Help & feedback")
                } footer: {
                    Text("Prvital \(AppInfo.versionBuild)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .prvioListRow()
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

            Group {
                if profile.displayName.isEmpty {
                    Text("Your profile")
                } else {
                    Text(verbatim: profile.displayName)
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.displayName.isEmpty ? Text("Your profile") : Text(profile.displayName))
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return SettingsView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
