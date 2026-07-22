import SwiftUI

/// The supportive daily-companion card shown at the top of the Dashboard. Purely
/// presentational: it takes an already-composed `CompanionMessage` and renders a
/// mood icon, a headline and a warm subline.
struct DailyCompanionCard: View {
    let message: CompanionMessage
    /// When set, a small "x" appears in the corner to hide the card for this
    /// session (the dashboard passes this; it reappears on the next launch).
    var onDismiss: (() -> Void)? = nil

    private var symbol: String {
        switch message.mood {
        case .gettingStarted: return "hand.wave.fill"
        case .celebrating: return "sun.max.fill"
        case .steady: return "leaf.fill"
        case .encouraging: return "sparkles"
        }
    }

    private var tint: Color {
        switch message.mood {
        case .gettingStarted: return Theme.accent
        case .celebrating: return Theme.zoneInRange
        case .steady: return Theme.accent
        case .encouraging: return Theme.zoneWarning
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 46, height: 46)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(message.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message.subline)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.headline). \(message.subline)")
        .overlay(alignment: .topTrailing) { dismissButton }
    }

    /// A small close control, shown only when the card is dismissible.
    @ViewBuilder private var dismissButton: some View {
        if let onDismiss {
            Button {
                Haptics.play(.light)
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        DailyCompanionCard(message: CompanionMessage(mood: .celebrating,
            headline: "You're doing great today", subline: "78% in range so far — lovely work. You're on a 3-day streak."))
        DailyCompanionCard(message: CompanionMessage(mood: .encouraging,
            headline: "Every reading is a fresh start", subline: "Today's been bumpy, and that's okay."))
    }
    .padding()
    .background(Theme.background)
}
