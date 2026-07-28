import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Create or edit a carbohydrate entry, with the quick-gram chip row and
/// one-tap favorite meals.
struct CarbEntrySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existing: CarbEntry?

    // Favorites are convenience presets, not medical records, so — like
    // `LogLabA1cSheet` — they read reactively via `@Query` and write straight
    // through the view's `modelContext` rather than the audited `EntryStore`.
    @Query(sort: \FavoriteMeal.createdAt) private var favorites: [FavoriteMeal]

    // Starts at 0 — the person types what they actually ate (a prefilled 40 g
    // was one habit-tap away from logging a meal that never happened). Save
    // stays disabled until a real amount is entered.
    @State private var grams: Double = 0
    @State private var timestamp = Date()
    @State private var mealType: MealType = .lunch
    /// Main meals already logged today — shown disabled in the picker so
    /// "lunch" can't be logged twice by reflex. Snacks repeat freely.
    @State private var takenMainMealsToday: Set<MealType> = []
    @State private var food = ""
    @State private var note = ""
    @State private var selectedTags: Set<ObservationTag> = []
    @State private var showingFood = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    /// The favorite whose tap pre-filled the fields, so saving can bump its
    /// usage stats. Nil when the user typed the entry from scratch.
    @State private var filledFromFavoriteID: UUID?
    @State private var saveAsFavorite = false
    @State private var showingFavoriteNamePrompt = false
    @State private var favoriteName = ""
    /// The connected glucose story for an existing meal (before → after + IOB).
    @State private var impact: EventInsight?

    var body: some View {
        NavigationStack {
            Form {
                if let impact, impact.hasContext {
                    Section("Impact") {
                        EventImpactSection(insight: impact,
                                           unit: env.preferences.glucoseUnit,
                                           thresholds: env.preferences.thresholds)
                    }
                }
                if existing == nil, !favorites.isEmpty {
                    // Vertical rows instead of a horizontal chip strip — a long
                    // meal name truncates gracefully in place of one huge chip
                    // pushing everything off-screen (device feedback).
                    Section("Favorites") {
                        ForEach(rankedFavorites) { favorite in
                            Button {
                                fill(from: favorite)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: favorite.mealType.symbol)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.zoneHigh)
                                        .frame(width: 32, height: 32)
                                        .background(Theme.zoneHigh.opacity(0.12), in: .circle)
                                    Text(favorite.name)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text("\(favorite.grams.formatted()) g")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textSecondary)
                                        .monospacedDigit()
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section {
                    // Just the box — you type the amount (device feedback: no
                    // stepper, no preset chips here).
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        TextField("0", value: $grams, format: .number)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.zoneHigh)
                            .keyboardType(.decimalPad)
                            .fixedSize()
                            .accessibilityLabel("Carbohydrate grams")
                        Text("g")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.zoneHigh)
                        Spacer()
                    }
                    .onChange(of: grams) { _, value in
                        if value < 0 { grams = 0 } else if value > 300 { grams = 300 }
                    }
                }
                if existing == nil {
                    Section {
                        Button {
                            Haptics.play(.selection)
                            showingFood = true
                        } label: {
                            Label("Search or scan food", systemImage: "barcode.viewfinder")
                                .foregroundStyle(Theme.accent)
                        }
                    } footer: {
                        Text("Look up a food's exact carbs from Open Food Facts by name or barcode.")
                    }
                }
                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.label, systemImage: type.symbol)
                                .tag(type)
                                .selectionDisabled(disabledMealTypes.contains(type))
                        }
                    }
                    TextField("Food (optional)", text: $food)
                    DatePicker("Time", selection: $timestamp)
                }
                Section("Tags") { EntryTagPicker(selected: $selectedTags) }
                Section("Note") { TextField("Optional", text: $note, axis: .vertical) }
                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(photoData == nil ? "Add meal photo" : "Change photo", systemImage: "camera")
                            .foregroundStyle(Theme.accent)
                    }
                    #if canImport(UIKit)
                    if let photoData, let uiImage = UIImage(data: photoData) {
                        HStack(spacing: 12) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Spacer()
                            Button("Remove", role: .destructive) {
                                self.photoData = nil
                                self.photoItem = nil
                                Haptics.play(.selection)
                            }
                        }
                    }
                    #endif
                }
                if existing == nil {
                    Section {
                        Toggle(isOn: $saveAsFavorite) {
                            Label("Save as favorite", systemImage: saveAsFavorite ? "star.fill" : "star")
                                .foregroundStyle(saveAsFavorite ? Theme.zoneHigh : Theme.textSecondary)
                        }
                        .tint(Theme.zoneHigh)
                        .onChange(of: saveAsFavorite) { _, _ in Haptics.play(.selection) }
                    } footer: {
                        Text("Keeps this meal one tap away next time you log carbs.")
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let existing { env.entryStore.delete(existing) }
                            Haptics.play(.warning); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Log carbs" : "Edit carbs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(grams <= 0) }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .sheet(isPresented: $showingFood) {
                FoodSearchView(mealType: mealType) {
                    showingFood = false
                    dismiss()
                }
            }
            .alert("Name this favorite", isPresented: $showingFavoriteNamePrompt) {
                TextField("Name", text: $favoriteName)
                Button("Save") { completeSave() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A short name for this meal, e.g. \"Usual breakfast\".")
            }
        }
    }

    private func load() {
        guard let existing else {
            prepareNewEntryDefaults()
            return
        }
        grams = existing.grams
        timestamp = existing.timestamp
        mealType = existing.mealType
        food = existing.foodDescription ?? ""
        note = existing.note ?? ""
        photoData = existing.photo
        selectedTags = Set(existing.tags)
        computeImpact(for: existing)
    }

    /// The smart defaults for a fresh entry: which meal this most likely is.
    ///
    /// - Glucose LOW right now → this is hypo-treatment carbs, so suggest a
    ///   snack outright — never "Lunch" while someone treats a low.
    /// - Otherwise suggest by the clock (breakfast / lunch / dinner bands) —
    ///   but a main meal already logged today falls through to a snack, and it
    ///   also shows disabled in the picker so it can't be picked twice by reflex.
    private func prepareNewEntryDefaults() {
        let calendar = Calendar.current
        let now = Date()

        // Main meals already logged today (snacks repeat freely).
        let startOfDay = calendar.startOfDay(for: now)
        let todayDescriptor = FetchDescriptor<CarbEntry>(
            predicate: #Predicate { $0.timestamp >= startOfDay })
        let todays = (try? modelContext.fetch(todayDescriptor)) ?? []
        takenMainMealsToday = Set(todays.map(\.mealType))
            .intersection([.breakfast, .lunch, .dinner])

        // Is the latest fresh reading low?
        var latestDescriptor = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        latestDescriptor.fetchLimit = 1
        let latest = (try? modelContext.fetch(latestDescriptor))?.first
        let thresholds = env.preferences.thresholds
        let isLowNow = latest.map {
            now.timeIntervalSince($0.timestamp) <= 20 * 60
                && $0.valueMgdL < thresholds.targetLower
        } ?? false

        let hour = calendar.component(.hour, from: now)
        let daypartSnack: MealType = hour < 16 ? .morningSnack : .eveningSnack
        if isLowNow {
            mealType = daypartSnack
            return
        }
        let clockMeal: MealType? = switch hour {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: nil
        }
        if let clockMeal, !takenMainMealsToday.contains(clockMeal) {
            mealType = clockMeal
        } else {
            mealType = daypartSnack
        }
    }

    /// Picker rows shown disabled: main meals already logged today — only for
    /// a NEW entry dated today, and never the currently selected value (so an
    /// edit or an intentional re-selection is never trapped).
    private var disabledMealTypes: Set<MealType> {
        guard existing == nil, Calendar.current.isDateInToday(timestamp) else { return [] }
        return takenMainMealsToday.subtracting([mealType])
    }

    /// Reads the glucose around this meal and the insulin active at its time, so
    /// the editor can show the connected before → after + IOB story.
    private func computeImpact(for meal: CarbEntry) {
        let event = meal.timestamp
        let lo = event.addingTimeInterval(-60 * 60)
        let hi = event.addingTimeInterval(4 * 3600)
        let gDesc = FetchDescriptor<GlucoseReading>(
            predicate: #Predicate { $0.timestamp >= lo && $0.timestamp <= hi },
            sortBy: [SortDescriptor(\.timestamp)])
        let readings = (try? modelContext.fetch(gDesc)) ?? []
        let diaLo = event.addingTimeInterval(-env.preferences.bolusParameters.durationHours * 3600)
        let iDesc = FetchDescriptor<InsulinDose>(
            predicate: #Predicate { $0.timestamp >= diaLo && $0.timestamp <= event },
            sortBy: [SortDescriptor(\.timestamp)])
        let doses = (try? modelContext.fetch(iDesc)) ?? []
        impact = EventInsight.make(
            eventDate: event, excludingDoseID: nil,
            readings: readings, insulin: doses,
            bolus: env.preferences.bolusParameters)
    }

    private func save() {
        // The star was toggled on, so ask for a name first; the alert's Save
        // button finishes the entry via `completeSave`.
        if existing == nil, saveAsFavorite {
            favoriteName = defaultFavoriteName
            showingFavoriteNamePrompt = true
            return
        }
        completeSave()
    }

    private func completeSave() {
        if let existing {
            existing.grams = grams
            existing.timestamp = timestamp
            existing.mealType = mealType
            existing.foodDescription = food.isEmpty ? nil : food
            existing.note = note.isEmpty ? nil : note
            existing.photo = photoData
            existing.tags = Array(selectedTags)
            env.entryStore.touch(existing)
        } else {
            let entry = env.entryStore.addCarbs(
                grams: grams, timestamp: timestamp, mealType: mealType,
                foodDescription: food.isEmpty ? nil : food,
                note: note.isEmpty ? nil : note
            )
            // `init` doesn't take a photo or tags, so attach them after
            // creation and re-persist through the store's write path.
            if photoData != nil || !selectedTags.isEmpty {
                entry.photo = photoData
                entry.tags = Array(selectedTags)
                env.entryStore.touch(entry)
            }
            updateFavorites()
        }
        Haptics.play(.success)
        dismiss()
    }

    // MARK: Favorites

    /// Favorites ordered "you'd want this now" first: usual-time matches for the
    /// current clock time, then most-used / most-recently used.
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

    private var defaultFavoriteName: String {
        let trimmed = food.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Meal, \(grams.formatted()) g" : trimmed
    }

    /// Copies a favorite into the editable fields — the user still reviews and
    /// taps Save, nothing is logged yet.
    private func fill(from favorite: FavoriteMeal) {
        grams = favorite.grams
        mealType = favorite.mealType
        food = favorite.foodDescription ?? ""
        filledFromFavoriteID = favorite.id
        Haptics.play(.selection)
    }

    /// After a new entry is logged: persist the starred favorite (if any) and
    /// bump the usage stats of the favorite the sheet was filled from.
    private func updateFavorites() {
        var starred: FavoriteMeal?
        if saveAsFavorite { starred = upsertFavorite() }

        let logMinutes = FavoriteMealSuggester.minutesFromMidnight(of: timestamp)
        if let id = filledFromFavoriteID,
           let used = favorites.first(where: { $0.id == id }) {
            used.timesUsed += 1
            used.lastUsedAt = Date()
            used.usualMinutesFromMidnight = FavoriteMealSuggester.blendedUsualMinutes(
                current: used.usualMinutesFromMidnight, newMinutes: logMinutes
            )
        } else if let starred, starred.timesUsed == 0 {
            // A favorite born from this very entry: seed its usage so the
            // suggester can rank it right away.
            starred.timesUsed = 1
            starred.lastUsedAt = Date()
            starred.usualMinutesFromMidnight = logMinutes
        }
        try? modelContext.save()
    }

    /// Creates a favorite from the entered fields, or — when one with the same
    /// name already exists (case-insensitively) — refreshes that one in place so
    /// re-starring never duplicates.
    private func upsertFavorite() -> FavoriteMeal {
        let trimmed = favoriteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? defaultFavoriteName : trimmed
        let description = food.isEmpty ? nil : food

        if let match = favorites.first(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            match.grams = grams
            match.mealType = mealType
            match.foodDescription = description
            return match
        }
        let favorite = FavoriteMeal(
            name: name, grams: grams, mealType: mealType, foodDescription: description
        )
        modelContext.insert(favorite)
        return favorite
    }
}

