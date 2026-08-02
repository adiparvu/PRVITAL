import SwiftUI
import LocalAuthentication

/// Face ID / passcode gate over the whole app.
///
/// A medical journal is exactly the thing a borrowed, unlocked phone should not
/// expose, so with the toggle on the app covers itself the moment it leaves the
/// foreground and asks the system to authenticate on return. It uses
/// `.deviceOwnerAuthentication` — Face ID / Touch ID with the device passcode
/// as the built-in fallback — so nobody can lock themselves out.
///
/// Deliberately NOT persisted state: a fresh launch starts locked (when the
/// preference is on) and unlocks on first authentication.
@Observable
@MainActor
final class AppLock {
    private(set) var isLocked: Bool
    /// True while the system sheet is up, so scene-phase wobbles the sheet
    /// itself causes (active → inactive → active) don't re-trigger it.
    private var authenticating = false

    init(enabled: Bool) {
        isLocked = enabled
    }

    /// Covers the content. Called when the app leaves the foreground.
    func lock() {
        guard !authenticating else { return }
        isLocked = true
    }

    /// Brings up Face ID / passcode; clears the cover on success.
    func unlock() async {
        guard isLocked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the device: there is nothing to authenticate
            // against, so the gate cannot hold. Open rather than brick the app.
            isLocked = false
            return
        }
        let reason = String(localized: "Unlock your glucose journal")
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: reason)) ?? false
        if ok { isLocked = false }
    }
}

/// The opaque cover shown while locked: brand mark, one line, one button. The
/// content underneath is fully hidden (no blurred peek — values could still be
/// legible through a blur at glance distance).
struct AppLockScreen: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Prvital is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: unlock) {
                    Text("Unlock")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: .capsule)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}
