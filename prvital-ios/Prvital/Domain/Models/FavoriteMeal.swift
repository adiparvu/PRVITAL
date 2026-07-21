import Foundation
import SwiftData

/// A saved, frequently-eaten meal the user can re-log in one tap ("my usual
/// breakfast — 45 g"). Created from a logged carb entry or by hand; `timesUsed`
/// and `lastUsedAt` drive the "you usually have this around now" suggestions.
///
/// CloudKit-safe by construction: every stored property has a default, optionals
/// stand in for absent values, enums are stored raw, and there are no unique
/// constraints — so SwiftData can mirror it to the private CloudKit database.
@Model
final class FavoriteMeal {
    var id: UUID = UUID()
    /// The user-facing name, e.g. "Micul dejun obișnuit".
    var name: String = ""
    var grams: Double = 0
    var mealTypeRaw: String = MealType.lunch.rawValue
    /// What's in it, carried onto the logged entry ("2 slices rye + eggs").
    var foodDescription: String?
    /// Minutes from midnight of the user's typical time for this meal, learned
    /// from the entries it's logged with. Nil until first use.
    var usualMinutesFromMidnight: Int?
    var timesUsed: Int = 0
    var lastUsedAt: Date?
    var createdAt: Date = Date()

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .lunch }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        grams: Double = 0,
        mealType: MealType = .lunch,
        foodDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.grams = grams
        self.mealTypeRaw = mealType.rawValue
        self.foodDescription = foodDescription
        self.createdAt = Date()
    }
}
