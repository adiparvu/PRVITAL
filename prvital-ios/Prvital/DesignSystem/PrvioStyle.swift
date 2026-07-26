import SwiftUI

/// The "Prvio" menu language, ported from the user's other app at their request:
/// dark translucent cards the wallpaper breathes through, monochrome icons in
/// neutral squircles (colour is reserved for genuine semantics, like emergency),
/// title-first rows with quiet subtitles, and big hub rows instead of long lists.

// MARK: - Icon tile

/// A neutral squircle with a monochrome glyph — the Prvio row icon. Pass an
/// `emphasis` colour only when the meaning demands it (emergency red).
struct PrvioIconTile: View {
    let systemImage: String
    var emphasis: Color? = nil

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(emphasis ?? Theme.textPrimary.opacity(0.92))
            .frame(width: 30, height: 30)
            .background(
                Theme.textPrimary.opacity(0.08),
                in: .rect(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Row

/// A Prvio-style destination row: neutral tile, title, optional live subtitle.
/// The disclosure chevron comes from the containing `NavigationLink`/`List`.
struct PrvioRow: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    let systemImage: String
    var emphasis: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            PrvioIconTile(systemImage: systemImage, emphasis: emphasis)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dark glass row background

/// The Prvio card surface for list rows: frosted glass with a dark veil, so the
/// app background stays visible through every menu — darker and calmer than the
/// bright frosted rows elsewhere. Light mode gets only a whisper of the veil.
struct PrvioListRowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(colorScheme == .dark ? 0.30 : 0.05)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline.opacity(0.4)).frame(height: 0.5)
        }
    }
}

extension View {
    /// Prvio-style dark-glass background for a settings list row, with the
    /// reference app's tighter row insets — the frames match Prvio's height
    /// (device feedback: "the frames the same size as in Prvio").
    func prvioListRow() -> some View {
        listRowBackground(PrvioListRowBackground())
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    /// Prvio-style quiet section header: small, grey, sentence case — never
    /// the big bold title the default header ends up as under scaled type.
    func prvioSectionHeader() -> some View {
        font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .textCase(nil)
    }
}

// MARK: - Quick chip

/// One of the quick-action chips under the profile card (Prvio's
/// Documents / Finance / Inventory row): a coloured glyph over a dark glass
/// tile with a small label.
struct PrvioChipLabel: View {
    let systemImage: String
    let title: LocalizedStringKey
    var tint: Color = Theme.accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.05))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1)
        )
        .contentShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
