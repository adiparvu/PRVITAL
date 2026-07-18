import SwiftUI

/// Sources & provenance. Lets the user pick the **primary** glucose source
/// (which drives provenance display and conflict priority) and see the
/// connection state of every registered source, connecting the ones that are
/// available but not yet linked.
struct SourcesSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    /// Bumped after a connection attempt so the (non-observable) source states
    /// are re-read and the rows refresh.
    @State private var refreshTick = 0

    private var primaryBinding: Binding<DataSource> {
        Binding(
            get: { env.registry.primarySource },
            set: { env.registry.primarySource = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Primary source", selection: primaryBinding) {
                    ForEach(DataSource.allCases) { source in
                        Label(source.displayName, systemImage: source.symbol)
                            .tag(source)
                    }
                }
            } header: {
                Text("Primary source")
            } footer: {
                Text("Your primary source labels every reading's provenance and wins when two sources report the same moment. You can change it at any time without losing data.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(env.registry.orderedSources, id: \.source) { source in
                    SourcesRow(
                        source: source,
                        isPrimary: source.source == env.registry.primarySource,
                        tick: refreshTick,
                        onConnect: { connect(source) }
                    )
                }
            } header: {
                Text("Registered sources")
            } footer: {
                Text("A connected source imports readings automatically. Manual entry is always available. CGM sensors like Dexcom and FreeStyle Libre appear here once your build is configured for them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                NavigationLink {
                    NightscoutSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cloud")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nightscout")
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                            Text(env.preferences.nightscout.isConfigured ? "Configured" : "Not set up")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } header: {
                Text("Self-hosted")
            } footer: {
                Text("Sync CGM readings from your own Nightscout site over the internet — no vendor account required.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func connect(_ source: GlucoseSource) {
        Haptics.play(.light)
        Task {
            try? await source.requestAccess()
            refreshTick += 1
        }
    }
}

// MARK: - Private helpers

/// One source row: name, symbol, connection state, and a Connect action when the
/// source is available but not yet linked.
private struct SourcesRow: View {
    let source: GlucoseSource
    let isPrimary: Bool
    /// Referenced only to make the row re-read `connectionState` after a connect.
    let tick: Int
    let onConnect: () -> Void

    var body: some View {
        let state = source.connectionState
        let descriptor = SourcesStateDescriptor(state: state)

        HStack(spacing: 12) {
            Image(systemName: source.source.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.displayName)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                    if isPrimary {
                        Text("Primary")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accentSoft, in: .capsule)
                            .foregroundStyle(Theme.accent)
                    }
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(descriptor.color)
                        .frame(width: 7, height: 7)
                    Text(descriptor.label)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            if descriptor.canConnect && source.source != .nightscout {
                Button("Connect", action: onConnect)
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.displayName), \(descriptor.label)\(isPrimary ? ", primary source" : "")")
        .accessibilityHint(descriptor.canConnect ? "Double tap Connect to link this source" : "")
    }
}

/// Maps a `SourceConnectionState` to a human label, indicator colour and whether
/// a Connect action should be offered.
private struct SourcesStateDescriptor {
    let label: String
    let color: Color
    let canConnect: Bool

    init(state: SourceConnectionState) {
        switch state {
        case .connected:
            label = "Connected"; color = Theme.zoneInRange; canConnect = false
        case .connecting:
            label = "Connecting…"; color = Theme.zoneHigh; canConnect = false
        case .needsAuthorization:
            label = "Needs authorization"; color = Theme.zoneHigh; canConnect = true
        case .notConnected:
            label = "Not connected"; color = Theme.textTertiary; canConnect = true
        case .unavailable:
            label = "Unavailable on this device"; color = Theme.textTertiary; canConnect = false
        case .failed(let message):
            label = message.isEmpty ? "Connection failed" : message
            color = Theme.zoneCritical; canConnect = true
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { SourcesSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
