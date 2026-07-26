import SwiftUI
import SwiftData

/// Identifies which full editor to present. Public so any screen can drive an
/// editor sheet with `.sheet(item:)`.
enum EntryEditorKind: String, Identifiable {
    case glucose, insulin, carbs, activity, observation
    var id: String { rawValue }

    /// Localized tile title. (`LocalizedStringKey` so the catalog translates it —
    /// a plain `String` here once shipped the tiles untranslated.)
    var titleKey: LocalizedStringKey {
        switch self {
        case .glucose: return "Glucose"
        case .insulin: return "Insulin"
        case .carbs: return "Carbs"
        case .activity: return "Activity"
        case .observation: return "Observation"
        }
    }
    /// One-line description under the tile title.
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .glucose: return "Log a reading"
        case .insulin: return "Dose & type"
        case .carbs: return "Meal & food"
        case .activity: return "Movement & sport"
        case .observation: return "Notes & symptoms"
        }
    }
    var symbol: String {
        switch self {
        case .glucose: return "drop.fill"
        case .insulin: return "syringe.fill"
        case .carbs: return "fork.knife"
        case .activity: return "figure.walk"
        case .observation: return "note.text"
        }
    }
    var tint: Color {
        switch self {
        case .glucose: return Theme.zoneCritical
        case .insulin: return Theme.accent
        case .carbs: return Theme.zoneHigh
        case .activity: return Theme.zoneInRange
        case .observation: return Theme.textSecondary
        }
    }
}

/// Presents the editor for a given kind. Reused by Dashboard, Journal and
/// History so editing is identical everywhere.
struct EntryEditor: View {
    let kind: EntryEditorKind
    var body: some View {
        switch kind {
        case .glucose: GlucoseEntrySheet()
        case .insulin: InsulinEntrySheet()
        case .carbs: CarbEntrySheet()
        case .activity: ActivityEntrySheet()
        case .observation: ObservationEntrySheet()
        }
    }
}

/// The quick-entry hub, built to be *contextual*: it opens with the current
/// glucose so the user logs with the number in front of them, surfaces a
/// treat-low shortcut when it matters, offers their favorite meals as true
/// one-tap logs, keeps the fast insulin/carb chips, and launches the full
/// editors from rich, localized tiles.
struct QuickEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FavoriteMeal.lastUsedAt, order: .reverse) private var favorites: [FavoriteMeal]

    @State private var editor: EntryEditorKind?
    @State private var showBolusCalculator = false
    @State private var showRuleOf15 = false
    @State private var showKetones = false
    @State private var showVoiceLog = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// The display-ready snapshot the widgets use — self-contained and cheap.
    private var snapshot: GlucoseSnapshot { SharedStore.load() }
    private var hasLiveReading: Bool { snapshot.updatedAt > .distantPast }
    private var currentZone: GlucoseZone {
        env.preferences.thresholds.zone(forMgdL: snapshot.mgdL)
    }
    private var showTreatLow: Bool {
        hasLiveReading && !snapshot.isStale && currentZone.isHypo
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if hasLiveReading {
                        contextBanner.appearTransition(delay: 0)
                    }
                    if showTreatLow {
                        treatLowButton.appearTransition(delay: 0.03)
                    }
                    if !rankedFavorites.isEmpty {
                        favoritesCard.appearTransition(delay: 0.06)
                    }
                    SectionCard("Quick insulin", systemImage: "syringe.fill") {
                        chipRow(env.preferences.insulinPresets.map { ("+\($0.formatted()) U", $0) }, tint: Theme.accent) { units in
                            env.entryStore.addInsulin(units: units)
                            Haptics.play(.success); dismiss()
                        }
                    }
                    .appearTransition(delay: 0.10)
                    SectionCard("Quick carbs", systemImage: "fork.knife") {
                        chipRow(env.preferences.carbPresets.map { ("\($0.formatted()) g", $0) }, tint: Theme.zoneHigh) { grams in
                            env.entryStore.addCarbs(grams: grams)
                            Haptics.play(.success); dismiss()
                        }
                    }
                    .appearTransition(delay: 0.14)

                    Button { Haptics.play(.selection); showVoiceLog = true } label: {
                        voiceLauncherRow
                    }
                    .buttonStyle(PressableCardStyle())
                    .appearTransition(delay: 0.16)

                    launcherGrid

                    if env.preferences.bolusParameters.isEnabled, env.preferences.bolusParameters.isValid {
                        bolusShortcut.appearTransition(delay: 0.42)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Add entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editor) { EntryEditor(kind: $0) }
            .sheet(isPresented: $showBolusCalculator) { BolusCalculatorView() }
            .sheet(isPresented: $showRuleOf15) { RuleOf15Sheet() }
            .sheet(isPresented: $showKetones) { LogKetoneSheet() }
            .sheet(isPresented: $showVoiceLog) { VoiceLogSheet() }
        }
    }

    // MARK: Context

    /// The current reading, so every log happens with the number in view.
    /// Grey + clock when the value is stale, zone-tinted when live.
    private var contextBanner: some View {
        let tint = snapshot.isStale ? Color.gray : Color(hex: snapshot.zoneColorHex)
        return HStack(spacing: 12) {
            Image(systemName: snapshot.isStale ? "clock" : snapshot.trendSymbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(snapshot.valueText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(snapshot.isStale ? Theme.textSecondary : Theme.textPrimary)
                    Text(snapshot.unitText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 4) {
                    Text(snapshot.zoneLabel)
                    Text("·")
                    Text(snapshot.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var treatLowButton: some View {
        Button {
            Haptics.play(.warning)
            showRuleOf15 = true
        } label: {
            Label("Treat low (Rule of 15)", systemImage: "cross.case.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(currentZone.color)
        .accessibilityHint("Opens a guided low-glucose treatment")
    }

    // MARK: Favorites

    /// Favorites ordered "you'd want this now" first (usual-time match, then
    /// most used). Unlike the carb editor, tapping here logs the meal directly —
    /// that's the one-tap promise of a favorite.
    private var rankedFavorites: [FavoriteMeal] {
        let ranked = FavoriteMealSuggester.ranked(
            favorites.map {
                FavoriteMealSuggester.Candidate(
                    id: $0.id, name: $0.name,
                    usualMinutesFromMidnight: $0.usualMinutesFromMidnight,
                    timesUsed: $0.timesUsed, lastUsedAt: $0.lastUsedAt
                )
            },
            nowMinutesFromMidnight: FavoriteMealSuggester.minutesFromMidnight(of: Date())
        )
        let byID = Dictionary(favorites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ranked.compactMap { byID[$0.id] }
    }

    private var favoritesCard: some View {
        SectionCard("Favorites", systemImage: "star.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rankedFavorites) { favorite in
                        Button {
                            logFavorite(favorite)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: favorite.mealType.symbol)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.zoneHigh)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(favorite.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text("\(favorite.grams.formatted()) g")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.zoneHigh.opacity(0.10), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.zoneHigh.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(PressableChipStyle())
                        .accessibilityLabel("Log \(favorite.name), \(favorite.grams.formatted()) grams")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Logs the favorite as a real carb entry and teaches it this use, exactly
    /// like the carb editor's fill-from-favorite path.
    private func logFavorite(_ favorite: FavoriteMeal) {
        let now = Date()
        env.entryStore.addCarbs(
            grams: favorite.grams, timestamp: now,
            mealType: favorite.mealType, foodDescription: favorite.foodDescription
        )
        favorite.timesUsed += 1
        favorite.lastUsedAt = now
        favorite.usualMinutesFromMidnight = FavoriteMealSuggester.blendedUsualMinutes(
            current: favorite.usualMinutesFromMidnight,
            newMinutes: FavoriteMealSuggester.minutesFromMidnight(of: now)
        )
        try? modelContext.save()
        Haptics.play(.success)
        dismiss()
    }

    // MARK: Launchers

    /// The voice-logging launcher: one sentence instead of three taps. Sits
    /// right under the quick chips because it serves the same "log it in two
    /// seconds" moment.
    private var voiceLauncherRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accentSoft, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Log by voice")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Say a meal, a dose or a reading")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var launcherGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array([EntryEditorKind.glucose, .insulin, .carbs, .activity].enumerated()), id: \.element) { index, kind in
                    Button { Haptics.play(.selection); editor = kind } label: { launcherTile(kind) }
                        .buttonStyle(PressableCardStyle())
                        .appearTransition(delay: 0.18 + Double(index) * 0.05)
                }
            }
            Button { Haptics.play(.selection); editor = .observation } label: {
                launcherRow(.observation)
            }
            .buttonStyle(PressableCardStyle())
            .appearTransition(delay: 0.38)
            Button { Haptics.play(.selection); showKetones = true } label: {
                ketoneLauncherRow
            }
            .buttonStyle(PressableCardStyle())
            .appearTransition(delay: 0.40)
        }
    }

    /// The ketone launcher — a full-width row like the observation launcher, but
    /// opening the ketone sheet (ketone logging moved here from the sick-day
    /// screen so all logging lives in one place).
    private var ketoneLauncherRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.triangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.zoneWarning)
                .frame(width: 42, height: 42)
                .background(Theme.zoneWarning.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ketones")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Blood or urine reading")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// A square-ish grid tile: tinted icon circle, localized title + subtitle.
    private func launcherTile(_ kind: EntryEditorKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(kind.tint)
                .frame(width: 42, height: 42)
                .background(kind.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(kind.subtitleKey)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// The full-width variant used for the odd fifth launcher, so the grid never
    /// leaves a hole.
    private func launcherRow(_ kind: EntryEditorKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(kind.tint)
                .frame(width: 42, height: 42)
                .background(kind.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(kind.subtitleKey)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .glassCard(cornerRadius: 18, padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var bolusShortcut: some View {
        Button {
            Haptics.play(.selection)
            showBolusCalculator = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "function")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bolus calculator")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Suggests a dose from carbs, glucose, IOB & COB")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassCard(cornerRadius: 18, padding: 14)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Chips

    private func chipRow(_ items: [(String, Double)], tint: Color, action: @escaping (Double) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    QuickChip(label: item.0, tint: tint) { action(item.1) }
                }
            }
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return QuickEntrySheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}
