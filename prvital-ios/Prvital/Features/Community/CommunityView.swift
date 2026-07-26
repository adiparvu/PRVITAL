import SwiftUI

/// The community leaderboard: country / continent / global boards built on the
/// public CloudKit database, strictly opt-in. Only the pseudonym, badge points,
/// badge-level count and chosen country are shared — never medical data.
struct CommunityView: View {
    @Environment(AppEnvironment.self) private var env

    /// The score to publish, computed by the Achievements gallery.
    let points: Int
    let badges: Int

    private let client = CommunityClient()

    @State private var scope: LeaderboardScope = .country
    @State private var entries: [LeaderboardEntry] = []
    @State private var loading = false
    @State private var loadFailed = false
    @State private var accountMissing = false
    // Join-form state.
    @State private var draftHandle = ""
    @State private var draftCountry = Locale.current.region?.identifier ?? "RO"
    @State private var joining = false

    var body: some View {
        Group {
            if env.preferences.community.enabled {
                boardList
            } else {
                joinForm
            }
        }
        .prvitalTabBackground()
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Opt-in

    private var joinForm: some View {
        Form {
            Section {
                Text("Compete on points from your badges with people across your country, your continent and the world. Joining shares ONLY your nickname, your points, your badge count and the country you pick — never glucose values or any medical data. You can leave at any time and your entry is deleted.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .glassListRow()

            Section {
                TextField("Nickname", text: $draftHandle)
                    .textInputAutocapitalization(.words)
                Picker("Country", selection: $draftCountry) {
                    ForEach(countryCodes, id: \.self) { code in
                        Text("\(WorldContinents.flag(forCountry: code)) \(countryName(code))").tag(code)
                    }
                }
            } footer: {
                Text("Your nickname is public on the leaderboard. Pick anything — it doesn't have to be your name.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Button {
                    join()
                } label: {
                    if joining {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Join the leaderboard", systemImage: "trophy.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(joining || draftHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowBackground(Color.clear)
            } footer: {
                if accountMissing {
                    Text("Joining needs an iCloud account signed in on this device.")
                        .font(.footnote)
                        .foregroundStyle(Theme.zoneWarning)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            if draftHandle.isEmpty {
                draftHandle = env.profile.current().displayName
            }
        }
    }

    private func join() {
        Haptics.play(.selection)
        joining = true
        accountMissing = false
        Task {
            guard await client.accountAvailable() else {
                accountMissing = true
                joining = false
                return
            }
            do {
                try await client.publish(handle: draftHandle, points: points, badges: badges,
                                         country: draftCountry, force: true)
                var prefs = env.preferences.community
                prefs.enabled = true
                prefs.handle = draftHandle
                prefs.countryCode = draftCountry.uppercased()
                env.preferences.community = prefs
                Haptics.play(.success)
                await reload()
            } catch {
                loadFailed = true
            }
            joining = false
        }
    }

    // MARK: Board

    private var boardList: some View {
        List {
            Section {
                Picker("Board", selection: $scope) {
                    ForEach(LeaderboardScope.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }

            Section {
                if loading && entries.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if loadFailed {
                    Text("The leaderboard couldn't load. Pull to try again.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else if entries.isEmpty {
                    Text("No one here yet — your entry makes it a race.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(rank: index + 1, entry: entry)
                    }
                }
            } header: {
                Text(scopeHeader)
            } footer: {
                Text("Top 50 by badge points. Scores carry no medical data.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Button(role: .destructive) {
                    leave()
                } label: {
                    Label("Leave the leaderboard", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Leaving deletes your entry from the leaderboard.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .refreshable { await reload() }
        .task(id: scope) { await reload() }
        .onAppear {
            // Keep the published score fresh whenever the board is opened.
            let prefs = env.preferences.community
            Task {
                try? await client.publish(handle: prefs.handle, points: points,
                                          badges: badges, country: prefs.countryCode)
            }
        }
    }

    private var scopeHeader: String {
        let prefs = env.preferences.community
        switch scope {
        case .country:
            return "\(WorldContinents.flag(forCountry: prefs.countryCode)) \(countryName(prefs.countryCode))"
        case .continent:
            return WorldContinents.displayName(
                forContinent: WorldContinents.continent(forCountry: prefs.countryCode) ?? "")
        case .global:
            return String(localized: "Global")
        }
    }

    private func reload() async {
        loading = true
        loadFailed = false
        do {
            entries = try await client.top(scope: scope, country: env.preferences.community.countryCode)
        } catch {
            loadFailed = true
        }
        loading = false
    }

    private func leave() {
        Haptics.play(.selection)
        Task {
            try? await client.withdraw()
            var prefs = env.preferences.community
            prefs.enabled = false
            env.preferences.community = prefs
            entries = []
        }
    }

    // MARK: Countries

    private var countryCodes: [String] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && WorldContinents.continent(forCountry: $0) != nil }
            .sorted { countryName($0) < countryName($1) }
    }

    private func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

/// One leaderboard row: rank, flag + pseudonym, badge count, points. The
/// caller's own entry is tinted.
private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry

    private var rankBadge: String? {
        switch rank {
        case 1: "🥇"
        case 2: "🥈"
        case 3: "🥉"
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let rankBadge {
                    Text(rankBadge).font(.title3)
                } else {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(WorldContinents.flag(forCountry: entry.country)) \(entry.handle)")
                    .font(.subheadline.weight(entry.isMe ? .bold : .semibold))
                    .foregroundStyle(entry.isMe ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)
                Text("\(entry.badges) badge levels")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(entry.points) p")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(entry.isMe ? Theme.accent : Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(entry.handle), \(entry.points) points")
    }
}
