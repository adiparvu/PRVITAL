import SwiftUI

/// Configure a self-hosted **Nightscout** connection: the site URL and an
/// optional access token. Saving validates the site with a live fetch and shows
/// the result, so the user knows the link works before relying on it.
struct NightscoutSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var urlString = ""
    @State private var token = ""
    @State private var isTesting = false
    @State private var result: TestResult?

    private var unit: GlucoseUnit { env.preferences.glucoseUnit }
    private var trimmedURL: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The dedup watermark left by `NightscoutUploader` — the newest record
    /// timestamp already mirrored up to the site, if uploading has run.
    private var lastUpload: Date? {
        (UserDefaults(suiteName: AppSchema.appGroupIdentifier) ?? .standard)
            .object(forKey: NightscoutUploadPlanner.watermarkKey) as? Date
    }

    var body: some View {
        @Bindable var preferences = env.preferences
        Form {
            Section {
                TextField("https://your-site.example.com", text: $urlString)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Access token (optional)", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Connection")
            } footer: {
                Text("Enter your Nightscout site address and an access token created under Admin Tools → Subjects. Readings are fetched directly from your server to this device — the address and token are never sent anywhere else.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Button(action: saveAndTest) {
                    HStack {
                        Text(isTesting ? "Testing…" : "Save & test connection")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || trimmedURL.isEmpty)

                if let result {
                    Label {
                        Text(result.message)
                            .font(.footnote)
                            .foregroundStyle(result.isSuccess ? Theme.zoneInRange : Theme.zoneCritical)
                    } icon: {
                        Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.isSuccess ? Theme.zoneInRange : Theme.zoneCritical)
                    }
                }
            }
            .glassListRow()

            Section {
                Toggle("Upload my entries", isOn: $preferences.nightscoutUploadEnabled)
            } header: {
                Text("Upload")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sends the glucose, carbs and insulin you log in Prvital to your Nightscout site. Only entries you typed in — never data that came from Nightscout or Health.")
                    if let lastUpload {
                        Text("Last upload: \(lastUpload.formatted(date: .abbreviated, time: .shortened)).")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            if env.preferences.nightscout.isConfigured {
                Section {
                    Button(role: .destructive, action: remove) {
                        Text("Remove Nightscout")
                    }
                }
                .glassListRow()
            }
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Nightscout")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let config = env.preferences.nightscout
            urlString = config.urlString
            token = config.token
        }
    }

    // MARK: Actions

    private func saveAndTest() {
        Haptics.play(.light)
        env.preferences.nightscout = NightscoutConfig(urlString: trimmedURL, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let source = env.registry.source(for: .nightscout) as? NightscoutGlucoseSource else { return }

        isTesting = true
        result = nil
        Task {
            do {
                try await source.requestAccess()
                let latest = try await source.fetchLatest()
                if let latest {
                    result = .success("Connected — latest reading \(GlucoseFormatting.labeled(mgdL: latest.valueMgdL, unit: unit)).")
                } else {
                    result = .success("Connected — no recent readings on the site yet.")
                }
            } catch {
                result = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func remove() {
        Haptics.play(.warning)
        env.preferences.nightscout = .empty
        urlString = ""
        token = ""
        result = nil
        if let source = env.registry.source(for: .nightscout) as? NightscoutGlucoseSource {
            source.refreshConnectionState()
        }
    }
}

private enum TestResult {
    case success(String)
    case failure(String)

    var isSuccess: Bool { if case .success = self { return true } else { return false } }
    var message: String {
        switch self {
        case .success(let m), .failure(let m): return m
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { NightscoutSettingsView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
