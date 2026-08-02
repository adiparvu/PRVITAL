import SwiftUI

/// Privacy dashboard. One independent toggle per `ConsentScope`, each with a
/// plain-language rationale. Turning a scope on records the user's intent and,
/// for Apple Health, kicks off the system authorization request. Turning it off
/// revokes the grant. Every change is mirrored into the audit trail by the store.
struct PrivacyDashboardView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                PrivacyHeaderCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(ConsentScope.allCases) { scope in
                    PrivacyConsentRow(scope: scope, isOn: consentBinding(for: scope))
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Each permission is optional and independent — grant only what you need, and revoke any of them at any time. Nothing is enabled by default.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()

            Section {
                Toggle(isOn: appLockBinding) {
                    Label {
                        Text("Lock with Face ID")
                            .foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "faceid").foregroundStyle(Theme.accent)
                    }
                }
                .tint(Theme.accent)
            } header: {
                Text("Security")
            } footer: {
                Text("Ask for Face ID or your passcode every time the app opens, so your journal stays private even on an unlocked phone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassListRow()
        }
        .scrollContentBackground(.hidden)
        .prvitalScreenBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { env.preferences.appLockEnabled },
            set: { on in
                Haptics.play(.selection)
                env.preferences.appLockEnabled = on
            }
        )
    }

    private func consentBinding(for scope: ConsentScope) -> Binding<Bool> {
        Binding(
            get: { env.consent.isGranted(scope) },
            set: { granted in
                Haptics.play(.selection)
                env.consent.setGranted(scope, granted)
                if scope == .healthKit, granted {
                    Task { try? await env.healthKit.requestAuthorization() }
                }
            }
        )
    }
}

// MARK: - Private helpers

/// The explanatory card at the top of the dashboard.
private struct PrivacyHeaderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Private by design").font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: "lock.shield.fill").foregroundStyle(Theme.accent)
            }
            Text("Your medical data stays on your device and is never sold or used for advertising. Nothing is shared until you explicitly grant a permission below, and you stay in control of each one.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A single consent scope: symbol, title, rationale and an independent toggle.
private struct PrivacyConsentRow: View {
    let scope: ConsentScope
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: scope.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(scope.title)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                    Text(scope.rationale)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel(scope.title)
        .accessibilityHint(scope.rationale)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack { PrivacyDashboardView() }
        .environment(env)
        .modelContainer(env.modelContainer)
}
