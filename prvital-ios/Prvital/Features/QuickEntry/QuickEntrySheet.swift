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

/// The quick-entry *composer*, rebuilt from scratch: instead of chips that save
/// and dismiss instantly one at a time, taps accumulate into a visible basket —
/// a meal and its bolus built together, checked together, saved together as one
/// moment. Opens at half height with everything within thumb reach.
///
///  - tap a chip / favorite → it enters the basket (tap again to remove);
///  - hold a chip → instant save, the old one-tap fast path;
///  - ± fine-tuning appears for whatever is in the basket;
///  - with the bolus calculator configured, a "Suggested: X U" chip derives the
///    dose from the basket's carbs, the live glucose and IOB — one tap adopts it;
///  - one Save button writes everything, linked as a single moment.
struct QuickEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FavoriteMeal.lastUsedAt, order: .reverse) private var favorites: [FavoriteMeal]
    @Query private var recentInsulin: [InsulinDose]

    /// Everything staged for the single Save.
    private struct Basket: Equatable {
        var carbsGrams: Double?
        var carbsDescription: String?
        var carbsMealType: MealType?
        var insulinUnits: Double?
        var isEmpty: Bool { carbsGrams == nil && insulinUnits == nil }
    }

    @State private var basket = Basket()
    /// The favorite currently in the basket, so saving can teach its stats.
    @State private var selectedFavoriteID: UUID?

    @State private var editor: EntryEditorKind?
    @State private var showBolusCalculator = false
    @State private var showRuleOf15 = false
    @State private var showKetones = false
    @State private var showVoiceLog = false

    init() {
        // Only the doses that can still carry insulin-on-board — bounded.
        let cutoff = Date().addingTimeInterval(-8 * 3600)
        _recentInsulin = Query(filter: #Predicate<InsulinDose> { $0.timestamp >= cutoff })
    }

    // MARK: Context

    /// The display-ready snapshot the widgets use — self-contained and cheap.
    private var snapshot: GlucoseSnapshot { SharedStore.load() }
    private var hasLiveReading: Bool { snapshot.updatedAt > .distantPast }
    private var currentZone: GlucoseZone {
        env.preferences.thresholds.zone(forMgdL: snapshot.mgdL)
    }
    private var showTreatLow: Bool {
        hasLiveReading && !snapshot.isStale && currentZone.isHypo
    }

    private var bolusParameters: BolusParameters { env.preferences.bolusParameters }

    /// Live insulin-on-board — the number to glance at before doubling a dose.
    private var insulinOnBoard: Double {
        guard bolusParameters.isValid else { return 0 }
        return InsulinMath.activeInsulin(doses: recentInsulin, at: Date(), parameters: bolusParameters)
    }

    /// The calculator's dose for the basket's carbs at the live glucose, IOB
    /// deducted — offered as a chip only when it is safe to derive one: the
    /// calculator is configured, carbs are staged, and there are no warnings
    /// (a low, a stale reading or a clamped dose must send the user to the
    /// full calculator, not to a one-tap number).
    private var suggestedUnits: Double? {
        guard bolusParameters.isEnabled, bolusParameters.isValid,
              let grams = basket.carbsGrams else { return nil }
        let estimate = InsulinMath.suggestBolus(
            carbs: grams,
            currentMgdL: (hasLiveReading && !snapshot.isStale) ? snapshot.mgdL : nil,
            activeInsulin: insulinOnBoard,
            parameters: bolusParameters,
            thresholds: env.preferences.thresholds
        )
        guard estimate.warnings.isEmpty else { return nil }
        let rounded = (estimate.suggested * 2).rounded() / 2   // pen resolution
        return rounded >= 0.5 ? rounded : nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if hasLiveReading {
                        contextBanner.appearTransition(delay: 0)
                    }
                    if showTreatLow {
                        treatLowButton.appearTransition(delay: 0.03)
                    }
                    if !rankedFavorites.isEmpty {
                        favoritesCard.appearTransition(delay: 0.06)
                    }
                    insulinCard.appearTransition(delay: 0.10)
                    carbsCard.appearTransition(delay: 0.14)
                    if basket.isEmpty {
                        Text("Tap the chips to combine a meal and its bolus, then save them together.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .appearTransition(delay: 0.18)
                    }
                    iconRow.appearTransition(delay: 0.20)
                }
                .padding()
                .padding(.bottom, 8)
            }
            .background(Theme.background)
            .navigationTitle("Add entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if !basket.isEmpty {
                    basketBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: basket)
            .sheet(item: $editor) { EntryEditor(kind: $0) }
            .sheet(isPresented: $showBolusCalculator) { BolusCalculatorView() }
            .sheet(isPresented: $showRuleOf15) { RuleOf15Sheet() }
            .sheet(isPresented: $showKetones) { LogKetoneSheet() }
            .sheet(isPresented: $showVoiceLog) { VoiceLogSheet() }
        }
        // Half height first: everything essential in thumb reach; pull up for
        // the icon row and longer favorite lists.
        .presentationDetents([.medium, .large])
    }

    // MARK: Context banner

    /// The current reading — every log happens with the number in view — plus
    /// live IOB, so a second bolus is never a surprise.
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
            if insulinOnBoard >= 0.05 {
                HStack(spacing: 4) {
                    Text("IOB")
                        .font(.caption2.weight(.semibold))
                    Text("\(insulinOnBoard.formatted(.number.precision(.fractionLength(1)))) U")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.accentSoft, in: .capsule)
                .accessibilityLabel("Insulin on board \(insulinOnBoard.formatted(.number.precision(.fractionLength(1)))) units")
            }
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
    /// most used). A tap stages the meal in the basket — editable, visible,
    /// confirmed with Save — instead of logging blind.
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
                        favoriteChip(favorite)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func favoriteChip(_ favorite: FavoriteMeal) -> some View {
        let isSelected = selectedFavoriteID == favorite.id
        return HStack(spacing: 8) {
            Image(systemName: favorite.mealType.symbol)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.white : Theme.zoneHigh)
            VStack(alignment: .leading, spacing: 0) {
                Text(favorite.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                    .lineLimit(1)
                Text("\(favorite.grams.formatted()) g")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Theme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.zoneHigh : Theme.zoneHigh.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.zoneHigh.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
        .contentShape(.capsule)
        .animation(.snappy, value: isSelected)
        .onTapGesture {
            Haptics.play(.selection)
            if isSelected {
                clearCarbs()
            } else {
                basket.carbsGrams = favorite.grams
                basket.carbsDescription = favorite.foodDescription ?? favorite.name
                basket.carbsMealType = favorite.mealType
                selectedFavoriteID = favorite.id
            }
        }
        .accessibilityLabel("\(favorite.name), \(favorite.grams.formatted()) grams")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Insulin & carbs

    private var insulinCard: some View {
        SectionCard("Quick insulin", systemImage: "syringe.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let suggested = suggestedUnits, basket.insulinUnits != suggested {
                            suggestionChip(suggested)
                        }
                        ForEach(env.preferences.insulinPresets, id: \.self) { units in
                            ComposerChip(
                                label: "+\(units.formatted()) U",
                                isSelected: basket.insulinUnits == units,
                                tint: Theme.accent
                            ) {
                                Haptics.play(.selection)
                                basket.insulinUnits = basket.insulinUnits == units ? nil : units
                            } onInstantSave: {
                                instantSaveInsulin(units)
                            }
                        }
                    }
                }
                if let units = basket.insulinUnits {
                    fineAdjustRow(
                        text: "\(units.formatted()) U", tint: Theme.accent,
                        minus: { basket.insulinUnits = max(0.5, units - 0.5) },
                        plus: { basket.insulinUnits = min(100, units + 0.5) }
                    )
                }
            }
        }
    }

    private var carbsCard: some View {
        SectionCard("Quick carbs", systemImage: "fork.knife") {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(env.preferences.carbPresets, id: \.self) { grams in
                            ComposerChip(
                                label: "\(grams.formatted()) g",
                                isSelected: basket.carbsGrams == grams && selectedFavoriteID == nil,
                                tint: Theme.zoneHigh
                            ) {
                                Haptics.play(.selection)
                                if basket.carbsGrams == grams, selectedFavoriteID == nil {
                                    clearCarbs()
                                } else {
                                    basket.carbsGrams = grams
                                    basket.carbsDescription = nil
                                    basket.carbsMealType = nil
                                    selectedFavoriteID = nil
                                }
                            } onInstantSave: {
                                instantSaveCarbs(grams)
                            }
                        }
                    }
                }
                if let grams = basket.carbsGrams {
                    fineAdjustRow(
                        text: "\(grams.formatted()) g", tint: Theme.zoneHigh,
                        minus: { basket.carbsGrams = max(5, grams - 5) },
                        plus: { basket.carbsGrams = min(400, grams + 5) }
                    )
                }
            }
        }
    }

    /// The calculator's dose as a one-tap chip — sparkles because it is derived,
    /// not preset. Only offered when the estimate carries no warnings.
    private func suggestionChip(_ suggested: Double) -> some View {
        Button {
            Haptics.play(.success)
            basket.insulinUnits = suggested
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("Suggested: \(suggested.formatted()) U")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Theme.accentSoft, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(PressableChipStyle())
    }

    /// ± fine-tuning for whatever sits in the basket (0.5 U / 5 g steps).
    private func fineAdjustRow(text: String, tint: Color,
                               minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Button { Haptics.play(.selection); minus() } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(tint.opacity(0.8))
            }
            .buttonStyle(.plain)
            Text(text)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 64)
            Button { Haptics.play(.selection); plus() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(tint.opacity(0.8))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .animation(.snappy, value: text)
    }

    // MARK: Everything else — one compact row

    /// The full editors and tools as a single row of round monochrome buttons
    /// (Prvio style) instead of a wall of tiles.
    private var iconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                iconButton("drop.fill", "Glucose") { editor = .glucose }
                iconButton("syringe.fill", "Insulin") { editor = .insulin }
                iconButton("fork.knife", "Carbs") { editor = .carbs }
                iconButton("figure.walk", "Activity") { editor = .activity }
                iconButton("note.text", "Observation") { editor = .observation }
                iconButton("drop.triangle.fill", "Ketones") { showKetones = true }
                iconButton("mic.fill", "Voice") { showVoiceLog = true }
                if bolusParameters.isEnabled, bolusParameters.isValid {
                    iconButton("function", "Bolus") { showBolusCalculator = true }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private func iconButton(_ symbol: String, _ label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.textPrimary.opacity(0.08), in: .circle)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableChipStyle())
    }

    // MARK: Basket bar

    /// The staged entries + the single Save, floating above the home indicator.
    private var basketBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let grams = basket.carbsGrams {
                        basketChip(
                            symbol: "fork.knife", tint: Theme.zoneHigh,
                            text: basket.carbsDescription.map { "\(grams.formatted()) g · \($0)" }
                                ?? "\(grams.formatted()) g",
                            remove: clearCarbs
                        )
                    }
                    if let units = basket.insulinUnits {
                        basketChip(
                            symbol: "syringe.fill", tint: Theme.accent,
                            text: "\(units.formatted()) U",
                            remove: { basket.insulinUnits = nil }
                        )
                    }
                }
            }
            Button {
                saveBasket()
            } label: {
                Label("Save", systemImage: "checkmark")
                    .font(.headline)
                    .padding(.horizontal, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func basketChip(symbol: String, tint: Color, text: String,
                            remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
            Button {
                Haptics.play(.selection)
                remove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: Capsule())
    }

    // MARK: Actions

    private func clearCarbs() {
        basket.carbsGrams = nil
        basket.carbsDescription = nil
        basket.carbsMealType = nil
        selectedFavoriteID = nil
    }

    /// Writes the whole basket as one moment. When both a meal and a dose are
    /// staged, only the meal announces on the Island — one sentence, one
    /// confirmation.
    private func saveBasket() {
        let now = Date()
        if let units = basket.insulinUnits {
            _ = env.entryStore.addInsulin(units: units, announces: basket.carbsGrams == nil)
        }
        if let grams = basket.carbsGrams {
            _ = env.entryStore.addCarbs(
                grams: grams, timestamp: now,
                mealType: basket.carbsMealType ?? MealTimeClassifier.mealType(for: now),
                foodDescription: basket.carbsDescription
            )
            // Teach the favorite this use, exactly like the carb editor does.
            if let id = selectedFavoriteID, let favorite = favorites.first(where: { $0.id == id }) {
                favorite.timesUsed += 1
                favorite.lastUsedAt = now
                favorite.usualMinutesFromMidnight = FavoriteMealSuggester.blendedUsualMinutes(
                    current: favorite.usualMinutesFromMidnight,
                    newMinutes: FavoriteMealSuggester.minutesFromMidnight(of: now)
                )
                try? modelContext.save()
            }
        }
        Haptics.play(.success)
        dismiss()
    }

    /// The hold-to-save fast path — the old one-tap behaviour, kept for speed.
    private func instantSaveInsulin(_ units: Double) {
        _ = env.entryStore.addInsulin(units: units)
        Haptics.play(.success)
        dismiss()
    }

    private func instantSaveCarbs(_ grams: Double) {
        _ = env.entryStore.addCarbs(grams: grams)
        Haptics.play(.success)
        dismiss()
    }
}

/// A preset chip that stages into the basket on tap and saves instantly on a
/// hold. Plain gestures rather than a Button so tap and long-press coexist.
private struct ComposerChip: View {
    let label: String
    let isSelected: Bool
    let tint: Color
    let onTap: () -> Void
    let onInstantSave: () -> Void

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 56, minHeight: 44)
            .background(isSelected ? tint : tint.opacity(0.12), in: .capsule)
            .foregroundStyle(isSelected ? Color.white : tint)
            .contentShape(.capsule)
            .animation(.snappy, value: isSelected)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.35) {
                Haptics.play(.success)
                onInstantSave()
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Tap to stage, hold to save instantly")
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return QuickEntrySheet()
        .environment(env)
        .modelContainer(env.modelContainer)
}
