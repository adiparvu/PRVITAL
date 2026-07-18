import SwiftUI

/// Sign-in screen for a credentialed cloud source (Dexcom Share, LibreLinkUp).
/// Credentials are written to the Keychain and validated with a live login, so
/// the user sees whether the connection works before relying on it.
struct CredentialSourceSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    let dataSource: DataSource
    let usernameLabel: String
    let usernameIsEmail: Bool
    let needsRegion: Bool
    let footerText: String

    @State private var username = ""
    @State private var password = ""
    @State private var regionOutsideUS = false
    @State private var isTesting = false
    @State private var result: CredentialTestResult?

    private var store: SourceCredentialStore { .shared }
    private var canTest: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isTesting
    }

    var body: some View {
        Form {
            Section {
                TextField(usernameLabel, text: $username)
                    .textContentType(usernameIsEmail ? .emailAddress : .username)
                    .keyboardType(usernameIsEmail ? .emailAddress : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if needsRegion {
                    Picker("Region", selection: $regionOutsideUS) {
                        Text("United States").tag(false)
                        Text("Outside the US").tag(true)
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Button(action: saveAndTest) {
                    HStack {
                        Text(isTesting ? "Testing…" : "Save & test connection")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(!canTest)

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
            } footer: {
                Text("Your password is stored only in this device's Keychain and sent solely to the service to sign in.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)

            if store.hasCredentials(for: dataSource) {
                Section {
                    Button(role: .destructive, action: remove) {
                        Text("Remove account")
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(dataSource.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    // MARK: Actions

    private func load() {
        guard let credentials = store.read(for: dataSource) else { return }
        username = credentials.username
        password = credentials.password
        regionOutsideUS = credentials.region.lowercased() == "ous"
    }

    private func saveAndTest() {
        Haptics.play(.light)
        let region = needsRegion ? (regionOutsideUS ? "ous" : "us") : ""
        store.save(SourceCredentials(username: username.trimmingCharacters(in: .whitespaces),
                                     password: password, region: region), for: dataSource)
        guard let source = env.registry.source(for: dataSource) else { return }

        isTesting = true
        result = nil
        Task {
            do {
                try await source.requestAccess()
                let latest = try await source.fetchLatest()
                if let latest {
                    result = .success("Connected — latest reading \(GlucoseFormatting.labeled(mgdL: latest.valueMgdL, unit: env.preferences.glucoseUnit)).")
                } else {
                    result = .success("Connected — no recent readings yet.")
                }
            } catch {
                result = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func remove() {
        Haptics.play(.warning)
        store.delete(for: dataSource)
        username = ""
        password = ""
        result = nil
        env.registry.source(for: dataSource)?.refreshConnectionState()
    }
}

private enum CredentialTestResult {
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
    return NavigationStack {
        CredentialSourceSettingsView(
            dataSource: .dexcom,
            usernameLabel: "Dexcom username",
            usernameIsEmail: false,
            needsRegion: true,
            footerText: "Sign in with your Dexcom account to import readings through Dexcom Share."
        )
    }
    .environment(env)
    .modelContainer(env.modelContainer)
}
