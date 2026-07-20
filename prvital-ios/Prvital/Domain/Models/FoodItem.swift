import Foundation
import SwiftData

/// A reusable food in the user's local library: its nutrition per 100 g plus an
/// optional barcode and typical serving. Foods are looked up from Open Food
/// Facts or entered by hand, saved once, then reused to log carbs precisely.
///
/// Like every synced model, every stored property has a default and there are no
/// unique constraints, so the record replicates safely through CloudKit.
@Model
final class FoodItem {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var barcode: String?
    var sourceRaw: String = FoodSource.manual.rawValue

    /// Nutrition per 100 g of the food.
    var carbsPer100g: Double = 0
    var fiberPer100g: Double?
    var sugarsPer100g: Double?
    var proteinPer100g: Double?
    var fatPer100g: Double?
    var energyKcalPer100g: Double?

    /// A typical serving in grams, when the source reports one (e.g. 30 g).
    var servingSizeGrams: Double?

    /// How many times the food has been logged — used to surface favourites.
    var useCount: Int = 0
    var lastUsedAt: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var source: FoodSource {
        get { FoodSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        carbsPer100g: Double,
        fiberPer100g: Double? = nil,
        sugarsPer100g: Double? = nil,
        proteinPer100g: Double? = nil,
        fatPer100g: Double? = nil,
        energyKcalPer100g: Double? = nil,
        servingSizeGrams: Double? = nil,
        source: FoodSource = .manual,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.carbsPer100g = carbsPer100g
        self.fiberPer100g = fiberPer100g
        self.sugarsPer100g = sugarsPer100g
        self.proteinPer100g = proteinPer100g
        self.fatPer100g = fatPer100g
        self.energyKcalPer100g = energyKcalPer100g
        self.servingSizeGrams = servingSizeGrams
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
