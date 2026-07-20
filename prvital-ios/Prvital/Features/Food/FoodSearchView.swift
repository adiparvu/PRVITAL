import SwiftUI
import SwiftData

/// Find a food by name or barcode, pick a portion, and log its carbs precisely.
///
/// Searches the Open Food Facts database on submit, offers a live barcode
/// scanner, and surfaces the user's previously-used foods as favourites. Picking
/// any food opens a portion editor that computes the carbs for the amount eaten.
struct FoodSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var mealType: MealType = .lunch
    /// Called after a food has been logged, so a hosting sheet can dismiss too.
    var onLogged: () -> Void = {}

    @Query(sort: \FoodItem.useCount, order: .reverse) private var library: [FoodItem]

    @State private var query = ""
    @State private var results: [OpenFoodFactsProduct] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var showingScanner = false
    @State private var portionTarget: FoodItem?

    private let client = OpenFoodFactsClient()

    private var favourites: [FoodItem] {
        Array(library.filter { $0.useCount > 0 }.prefix(15))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.zoneWarning)
                        .listRowBackground(Theme.surface)
                }

                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching Open Food Facts…")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)
                }

                if query.isEmpty {
                    favouritesSection
                } else if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { product in
                            Button { portionTarget = product.makeFoodItem() } label: {
                                foodRow(name: product.name, brand: product.brand,
                                        carbsPer100g: product.carbsPer100g, caption: nil)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                        }
                    }
                } else if !isSearching {
                    Text("Press search to look up “\(query)”, or scan a barcode.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search foods")
            .onSubmit(of: .search) { Task { await runSearch() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        errorText = nil
                        showingScanner = true
                    } label: {
                        Label("Scan", systemImage: "barcode.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $showingScanner) { scannerSheet }
            .sheet(item: $portionTarget) { food in
                FoodPortionView(food: food, mealType: mealType) {
                    portionTarget = nil
                    onLogged()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var favouritesSection: some View {
        if favourites.isEmpty {
            Section {
                EmptyStateView(
                    systemImage: "fork.knife",
                    title: "Search or scan a food",
                    message: "Look it up by name, or scan its barcode, to log exact carbs. Foods you use are saved here for next time."
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section("Recent foods") {
                ForEach(favourites) { food in
                    Button { portionTarget = food } label: {
                        foodRow(name: food.name, brand: food.brand,
                                carbsPer100g: food.carbsPer100g,
                                caption: "Used \(food.useCount)×")
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                }
            }
        }
    }

    private func foodRow(name: String, brand: String?, carbsPer100g: Double, caption: String?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let brand { Text(brand).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1) }
                else if let caption { Text(caption).font(.caption2).foregroundStyle(Theme.textTertiary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(carbsPer100g.formatted(.number.precision(.fractionLength(0...1)))) g")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.zoneHigh)
                Text("per 100 g").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .contentShape(.rect)
    }

    private var scannerSheet: some View {
        NavigationStack {
            Group {
                if BarcodeScannerView.isSupported {
                    BarcodeScannerView { code in
                        showingScanner = false
                        Task { await lookupBarcode(code) }
                    }
                    .ignoresSafeArea()
                } else {
                    EmptyStateView(
                        systemImage: "camera.metering.unknown",
                        title: "Scanning unavailable",
                        message: "Barcode scanning needs a device with a camera. Search by name instead."
                    )
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingScanner = false } }
            }
        }
    }

    private func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        isSearching = true
        errorText = nil
        defer { isSearching = false }
        do {
            results = try await client.search(name: term)
            if results.isEmpty { errorText = "No foods found for “\(term)”." }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Open Food Facts."
        }
    }

    private func lookupBarcode(_ code: String) async {
        isSearching = true
        errorText = nil
        defer { isSearching = false }
        do {
            if let product = try await client.product(barcode: code) {
                portionTarget = product.makeFoodItem()
            } else {
                errorText = "No product found for barcode \(code)."
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Open Food Facts."
        }
    }
}

/// Pick how much of a food was eaten and log the resulting carbohydrates.
struct FoodPortionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let food: FoodItem
    var mealType: MealType
    var onLogged: () -> Void

    @State private var portion: Double
    @State private var selectedMeal: MealType
    @State private var useNetCarbs = false

    init(food: FoodItem, mealType: MealType, onLogged: @escaping () -> Void) {
        self.food = food
        self.mealType = mealType
        self.onLogged = onLogged
        _portion = State(initialValue: food.servingSizeGrams ?? 100)
        _selectedMeal = State(initialValue: mealType)
    }

    private var hasFiber: Bool { (food.fiberPer100g ?? 0) > 0 }

    private var carbs: Double {
        CarbCalculator.carbs(
            portionGrams: portion,
            carbsPer100g: food.carbsPer100g,
            fiberPer100g: food.fiberPer100g,
            useNetCarbs: useNetCarbs
        )
    }

    private let portionPresets: [Double] = [30, 50, 100, 150, 200]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 4) {
                        Text("\(carbs.formatted(.number.precision(.fractionLength(0...1)))) g")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.zoneHigh)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: carbs)
                        Text(useNetCarbs ? "net carbs" : "carbs")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Portion") {
                    HStack {
                        Text("\(portion.formatted(.number.precision(.fractionLength(0)))) g")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Spacer()
                        Stepper("", value: $portion, in: 1...2000, step: 5).labelsHidden()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(portionPresets, id: \.self) { grams in
                                QuickChip(label: "\(Int(grams)) g",
                                          isSelected: portion == grams,
                                          tint: Theme.zoneHigh) {
                                    portion = grams; Haptics.play(.selection)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                    if hasFiber {
                        Toggle("Count net carbs (subtract fibre)", isOn: $useNetCarbs.animation(.snappy))
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Meal") {
                    Picker("Meal", selection: $selectedMeal) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Per 100 g") { nutritionGrid }
                    .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Log", action: log) }
            }
        }
    }

    private var nutritionGrid: some View {
        VStack(spacing: 8) {
            nutritionRow("Carbs", food.carbsPer100g, "g", Theme.zoneHigh)
            if let fiber = food.fiberPer100g { nutritionRow("Fibre", fiber, "g", Theme.zoneInRange) }
            if let sugars = food.sugarsPer100g { nutritionRow("Sugars", sugars, "g", Theme.zoneWarning) }
            if let protein = food.proteinPer100g { nutritionRow("Protein", protein, "g", Theme.accent) }
            if let fat = food.fatPer100g { nutritionRow("Fat", fat, "g", Theme.textSecondary) }
            if let kcal = food.energyKcalPer100g { nutritionRow("Energy", kcal, "kcal", Theme.textSecondary) }
        }
    }

    private func nutritionRow(_ title: LocalizedStringKey, _ value: Double, _ unit: String, _ tint: Color) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
        }
    }

    private func log() {
        env.entryStore.logFood(
            food,
            portionGrams: portion,
            mealType: selectedMeal,
            useNetCarbs: useNetCarbs
        )
        Haptics.play(.success)
        onLogged()
    }
}

extension OpenFoodFactsProduct {
    /// Builds a (detached) library food from a looked-up product. Persisted only
    /// when it's actually logged, via `EntryStore.logFood`.
    func makeFoodItem() -> FoodItem {
        FoodItem(
            name: name,
            brand: brand,
            barcode: barcode,
            carbsPer100g: carbsPer100g,
            fiberPer100g: fiberPer100g,
            sugarsPer100g: sugarsPer100g,
            proteinPer100g: proteinPer100g,
            fatPer100g: fatPer100g,
            energyKcalPer100g: energyKcalPer100g,
            servingSizeGrams: servingSizeGrams,
            source: .openFoodFacts
        )
    }
}
