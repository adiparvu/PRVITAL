import SwiftUI

/// First-run onboarding. A short, welcoming, privacy-first flow: a welcome step
/// that explains the privacy-by-design principles, a consent step where each
/// scope is granted independently, and a final step that marks onboarding
/// complete. Nothing is enabled by default; every choice is the user's.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var didSeedUnit = false
    private let lastStep = 3

    var body: some View {
        let profile = env.profile.current()

        return ZStack {
            Theme.background.ignoresSafeArea()

            TabView(selection: $step) {
                OnboardingWelcomeStep().tag(0)
                consentStep.tag(1)
                OnboardingPersonalizeStep(profile: profile).tag(2)
                OnboardingReadyStep().tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .animation(.easeInOut, value: step)
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar(profile: profile)
        }
        .interactiveDismissDisabled()
        .onAppear(perform: seedUnitFromLocale)
    }

    /// Seeds the glucose unit from the device region on first run so most of the
    /// world lands on mmol/L rather than a hardcoded mg/dL. The user still
    /// confirms on the personalization step.
    private func seedUnitFromLocale() {
        guard !didSeedUnit else { return }
        didSeedUnit = true
        env.preferences.glucoseUnit = GlucoseUnit.localeDefault()
    }

    // MARK: Steps

    private var consentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose what to enable")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Each permission is optional and independent. Turn on only what you want — you can change any of these later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                ForEach(Array(ConsentScope.allCases.enumerated()), id: \.element.id) { index, scope in
                    OnboardingConsentCard(scope: scope, isOn: consentBinding(for: scope))
                        .appearTransition(delay: Double(index) * 0.06)
                }
            }
            .padding(20)
        }
    }

    // MARK: Bottom bar

    private func bottomBar(profile: UserProfile) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Theme.accent : Theme.hairline)
                        .frame(width: index == step ? 20 : 7, height: 7)
                        .animation(.easeInOut, value: step)
                }
            }
            .accessibilityHidden(true)

            Button {
                advance(profile: profile)
            } label: {
                Text(step < lastStep ? "Continue" : "Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.brandGradient, in: .rect(cornerRadius: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint(step < lastStep ? "Goes to the next step" : "Finishes setup and opens the app")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func advance(profile: UserProfile) {
        if step < lastStep {
            Haptics.play(.selection)
            withAnimation { step += 1 }
        } else {
            Haptics.play(.success)
            env.profile.save(profile)
            env.consent.hasCompletedOnboarding = true
            dismiss()
        }
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

// MARK: - Steps

/// Welcome + privacy-by-design principles.
private struct OnboardingWelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Theme.brandGradient)
                        .accessibilityHidden(true)
                    Text("Prvital")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A calm, private place for your glucose, insulin, meals, activity and notes — all in one timeline.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Private by design, private by default")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    OnboardingPrinciple(symbol: "iphone", title: "Stays on your device", detail: "Your journal is stored locally and encrypted at rest.")
                        .appearTransition(delay: 0.05)
                    OnboardingPrinciple(symbol: "icloud.slash", title: "No cloud unless you ask", detail: "Sync uses only your own private iCloud — off until you enable it.")
                        .appearTransition(delay: 0.10)
                    OnboardingPrinciple(symbol: "dollarsign.circle", title: "Never sold, never ads", detail: "Your medical data is never sold or used for advertising.")
                        .appearTransition(delay: 0.15)
                    OnboardingPrinciple(symbol: "brain", title: "No training without consent", detail: "Nothing is used to train models unless you turn it on.")
                        .appearTransition(delay: 0.20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .padding(20)
        }
    }
}

/// Personalization: the unit the user thinks in, plus who they are and how they
/// manage diabetes. Reuses `Preferences` and the `UserProfile` so the app is set
/// up correctly from the first screen instead of on mg/dL + Type 1 defaults.
private struct OnboardingPersonalizeStep: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var profile: UserProfile

    private var unitBinding: Binding<GlucoseUnit> {
        Binding(
            get: { env.preferences.glucoseUnit },
            set: { env.preferences.glucoseUnit = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make it yours")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A few details so Prvital speaks your numbers. You can change any of this later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Glucose unit")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Picker("Glucose unit", selection: unitBinding) {
                        ForEach(GlucoseUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your name (optional)")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    TextField("Your name", text: $profile.displayName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Diabetes type")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Picker("Diabetes type", selection: $profile.diabetesType) {
                        ForEach(DiabetesType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    Text(profile.diabetesType.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("How you manage it")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Picker("Therapy", selection: $profile.therapy) {
                        ForEach(TherapyApproach.allCases) { approach in
                            Text(approach.displayName).tag(approach)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .padding(20)
        }
    }
}

/// Final confirmation step.
private struct OnboardingReadyStep: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("You're all set")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Start logging from the Dashboard or Journal whenever you like. You can revisit every permission, unit and reminder in Settings at any time.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .padding(.top, 60)
        }
    }
}

// MARK: - Private helpers

/// A single privacy principle row on the welcome step.
private struct OnboardingPrinciple: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

/// A consent scope card with symbol, title, rationale and an independent toggle.
private struct OnboardingConsentCard: View {
    let scope: ConsentScope
    @Binding var isOn: Bool

    var body: some View {
        // The whole card is the control, so tapping anywhere toggles the scope.
        // The Toggle is display-only (hit testing off) to avoid a double toggle.
        Button {
            isOn.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: scope.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(scope.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .allowsHitTesting(false)
                }
                Text(scope.rationale)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isOn ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scope.title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(scope.rationale)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return OnboardingView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
