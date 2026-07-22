import SwiftUI

/// Partner & caregiver sharing. Prvital has no account system and no cloud
/// middleman, so sharing is done the private way: you generate a read-only care
/// summary and send it to whoever you choose through the system share sheet. For
/// people who want continuous following, it points them to Nightscout (already
/// built in), which relays their CGM to a site only they control.
struct SharingView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var days = 14
    @State private var summary = ""

    private let periodOptions = [7, 14, 30, 90]

    var body: some View {
        Form {
            Section {
                Text("Share a private, read-only snapshot of how your glucose has been — time in range, average, estimated A1c and more — with a partner, parent or care team. It's generated on this device; nothing is sent until you choose who to share it with.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .glassListRow()

            Section {
                Picker("Period", selection: $days) {
                    ForEach(periodOptions, id: \.self) { d in
                        Text("Last \(d) days").tag(d)
                    }
                }
            } header: {
                Text("Care summary")
            }
            .glassListRow()

            Section {
                ShareLink(item: summary) {
                    Label("Share care summary", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .simultaneousGesture(TapGesture().onEnded { env.careShare.logPrepared() })
            } footer: {
                Text(summaryPreview)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            .glassListRow()

            Section {
                NavigationLink {
                    NightscoutSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.up.forward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Continuous following")
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Let someone follow your live glucose via Nightscout")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } header: {
                Text("Live sharing")
            } footer: {
                Text("For real-time following, Nightscout relays your CGM to a site you control, which a follower can open. It stays entirely within your own infrastructure — no third-party account.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { regenerate() }
        .onChange(of: days) { _, _ in regenerate() }
    }

    private var summaryPreview: String {
        summary.isEmpty ? "" : "Preview:\n\(summary)"
    }

    private func regenerate() {
        summary = env.careShare.summaryText(days: days)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { SharingView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
