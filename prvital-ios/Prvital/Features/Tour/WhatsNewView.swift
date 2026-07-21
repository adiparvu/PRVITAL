import SwiftUI

/// Helpers for the "What's new" feature tour.
enum WhatsNewTour {
    /// The app's marketing version (e.g. "1.0.0"), read from the bundle. There
    /// is deliberately no fallback to the build number: an unreadable Info.plist
    /// yields "0", which simply re-offers the tour after the next update.
    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
}

/// A Tide Guide-style feature tour: one promo page per marquee feature, each
/// with a large hero composition built from the app's own visual language, a
/// bold title and a glass description card, over a soft accent gradient.
///
/// Presented as a sheet — once per app version from `RootView`, and on demand
/// from Settings → "What's new". Finishing (Done or Skip) stamps
/// `Preferences.lastSeenWhatsNewVersion` so the automatic presentation never
/// repeats for this version.
struct WhatsNewView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    private let lastPage = 5

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                TabView(selection: $page) {
                    TourPage(
                        title: String(localized: "Glucose on your Lock Screen"),
                        description: String(localized: "Start a Live Activity and your latest reading, trend arrow and mini chart stay on the Lock Screen and in the Dynamic Island — no unlocking, no app-switching.")
                    ) { LiveActivityHero() }
                    .tag(0)

                    TourPage(
                        title: String(localized: "Widgets that tell the truth"),
                        description: String(localized: "Home Screen and Lock Screen widgets show your latest reading in its zone colour — and say exactly how old it is, so a stale number never looks fresh."),
                        tint: Theme.zoneInRange
                    ) { WidgetsHero() }
                    .tag(1)

                    TourPage(
                        title: String(localized: "Insights that find the patterns"),
                        description: String(localized: "Time in range, meal impact, overnight stability, rebounds — Prvital studies your data and can hand you a Monday-morning digest of how your week really went.")
                    ) { InsightsHero() }
                    .tag(2)

                    TourPage(
                        title: String(localized: "Safety, three ways"),
                        description: String(localized: "The Rule of 15 walks you through treating a low, sick-day mode keeps extra guidance close when you're unwell, and the emergency card tells a helper exactly what to do."),
                        tint: Theme.zoneCritical
                    ) { SafetyHero() }
                    .tag(3)

                    TourPage(
                        title: String(localized: "Log it before it's forgotten"),
                        description: String(localized: "Favorite meals, one-tap presets and the quick-entry hub get glucose, insulin, carbs and activity into your journal in seconds."),
                        tint: Theme.zoneHigh
                    ) { FavoritesHero() }
                    .tag(4)

                    TourPage(
                        title: String(localized: "Make it yours"),
                        description: String(localized: "Six accent themes carried across the app, widgets and watch — plus journal density and appearance options. Calm by default, personal by choice.")
                    ) { ThemesHero() }
                    .tag(5)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(.easeInOut, value: page)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if page < lastPage {
                        Button("Skip") { finish() }
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Theme.background flowing into a soft accent wash behind the hero — deep
    /// and Tide-dark in dark mode, airy in light, since both colours adapt.
    private var backdrop: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: Theme.accent.opacity(0.30), location: 0),
                    .init(color: Theme.accent.opacity(0.10), location: 0.45),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var bottomBar: some View {
        Button {
            advance()
        } label: {
            Text(page < lastPage ? "Continue" : "Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .accessibilityHint(page < lastPage ? "Goes to the next feature" : "Closes the tour")
    }

    private func advance() {
        if page < lastPage {
            Haptics.play(.selection)
            withAnimation { page += 1 }
        } else {
            finish()
        }
    }

    /// Marks this version's tour as seen and closes the sheet.
    private func finish() {
        Haptics.play(.success)
        env.preferences.lastSeenWhatsNewVersion = WhatsNewTour.currentVersion
        dismiss()
    }
}

// MARK: - Page scaffold

/// One promo page: hero visual, bold title, glass description card.
private struct TourPage<Hero: View>: View {
    let title: String
    let description: String
    let tint: Color
    let hero: Hero

    init(title: String, description: String, tint: Color = Theme.accent,
         @ViewBuilder hero: () -> Hero) {
        self.title = title
        self.description = description
        self.tint = tint
        self.hero = hero()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HeroCanvas(tint: tint) { hero }
                    .padding(.top, 4)

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .glassCard(cornerRadius: 22, padding: 18)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40) // keep clear of the page dots
        }
    }
}

/// The stage every hero stands on: a soft tinted glow, fixed height, and the
/// whole composition hidden from VoiceOver — it is purely decorative.
private struct HeroCanvas<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.30), .clear],
                                     center: .center, startRadius: 20, endRadius: 160))
                .frame(width: 320, height: 320)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// A tiny fixed sparkline used inside mock cards (normalised 0…1 y-values).
private struct SparklineShape: Shape {
    let points: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let step = rect.width / CGFloat(points.count - 1)
        path.move(to: CGPoint(x: 0, y: rect.height * (1 - points[0])))
        for (index, value) in points.enumerated().dropFirst() {
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: rect.height * (1 - value)))
        }
        return path
    }
}

// MARK: - Heroes
// Each hero is a lightweight mock built from shapes, SF Symbols and the app's
// theme — no screenshots, no assets. All are wrapped in `HeroCanvas`, which
// hides them from accessibility.

/// Page 1: a mock Dynamic Island capsule above a mock Lock Screen Live Activity.
private struct LiveActivityHero: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer(minLength: 0)
                Text("112")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.zoneInRange)
            }
            .padding(.horizontal, 16)
            .frame(width: 176, height: 40)
            .background(.black, in: .capsule)
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Prvital")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("now")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("112")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("mg/dL")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.zoneInRange)
                }
                SparklineShape(points: [0.30, 0.48, 0.40, 0.58, 0.52, 0.68, 0.62])
                    .stroke(Theme.accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 30)
            }
            .glassCard(cornerRadius: 24, padding: 16)
            .frame(width: 254)
        }
    }
}

/// Page 2: a mock Home Screen widget tile beside a Lock Screen gauge, with an
/// honest "minutes ago" staleness pill.
private struct WidgetsHero: View {
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Circle().fill(Theme.zoneInRange).frame(width: 9, height: 9)
                }
                Spacer(minLength: 0)
                Text("108")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("mg/dL")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text("4 min ago")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .frame(width: 148, height: 148)
            .background(Theme.surface, in: .rect(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: 0.66)
                        .stroke(Theme.zoneInRange, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("108")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 76, height: 76)

                HStack(spacing: 5) {
                    Circle().fill(Theme.zoneInRange).frame(width: 7, height: 7)
                    Circle().fill(Theme.zoneHigh).frame(width: 7, height: 7)
                    Circle().fill(Theme.zoneWarning).frame(width: 7, height: 7)
                    Circle().fill(Theme.zoneCritical).frame(width: 7, height: 7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface, in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
            }
        }
    }
}

/// Page 3: a mini week-bar chart in zone colours with a sparkles digest chip.
private struct InsightsHero: View {
    private let bars: [(height: CGFloat, color: Color)] = [
        (46, Theme.zoneInRange), (68, Theme.zoneInRange), (54, Theme.zoneHigh),
        (80, Theme.zoneInRange), (60, Theme.zoneWarning), (86, Theme.zoneInRange),
        (72, Theme.zoneInRange)
    ]

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Capsule()
                        .fill(bar.color.gradient)
                        .frame(width: 14, height: bar.height)
                }
            }
            .glassCard(cornerRadius: 22, padding: 18)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Your week: 74% in range")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .glassCard(cornerRadius: 16, padding: 12)
        }
    }
}

/// Page 4: the safety trio — Rule of 15, sick-day mode, emergency card.
private struct SafetyHero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            badge(color: Theme.zoneWarning, caption: "Rule of 15") {
                Text("15")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.zoneWarning)
            }
            badge(color: Theme.zoneHigh, caption: "Sick day", diameter: 88) {
                Image(systemName: "medical.thermometer.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.zoneHigh)
            }
            badge(color: Theme.zoneCritical, caption: "Emergency") {
                Image(systemName: "staroflife.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.zoneCritical)
            }
        }
    }

    private func badge(color: Color, caption: String, diameter: CGFloat = 72,
                       @ViewBuilder glyph: () -> some View) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.14))
                Circle().strokeBorder(color.opacity(0.55), lineWidth: 1.5)
                glyph()
            }
            .frame(width: diameter, height: diameter)
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Page 5: a mock favorite-meal row above the quick-add preset chips.
private struct FavoritesHero: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.zoneHigh)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oatmeal & berries")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("38 g carbs · logged 12×")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
            }
            .glassCard(cornerRadius: 20, padding: 14)
            .frame(width: 268)

            HStack(spacing: 8) {
                chip("+2 U", tint: Theme.accent)
                chip("40 g", tint: Theme.zoneInRange)
                chip("30 min", tint: Theme.zoneWarning)
            }
        }
    }

    private func chip(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint.opacity(0.14), in: .capsule)
            .foregroundStyle(tint)
    }
}

/// Page 6: the real accent-theme swatches, with the teal default ringed.
private struct ThemesHero: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)

            HStack(spacing: 14) {
                ForEach(AccentTheme.allCases) { theme in
                    Circle()
                        .fill(theme.swatch)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if theme == .default {
                                Circle()
                                    .strokeBorder(theme.swatch.opacity(0.45), lineWidth: 2)
                                    .frame(width: 42, height: 42)
                            }
                        }
                }
            }
            .glassCard(cornerRadius: 26, padding: 16)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return WhatsNewView()
        .environment(env)
        .modelContainer(env.modelContainer)
}
