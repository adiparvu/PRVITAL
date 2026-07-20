import Foundation

/// Classifies a time of day into a `MealType`.
///
/// Apple Health's dietary-carbohydrate samples carry no meal label, so when we
/// import them into the journal we infer a sensible meal from the hour. It stays
/// a pure function of the hour so it's trivially testable and the user can always
/// correct the meal afterwards.
enum MealTimeClassifier {
    /// Maps an hour-of-day (0...23) to the most likely meal.
    static func mealType(forHour hour: Int) -> MealType {
        switch hour {
        case 5..<10:  return .breakfast
        case 10..<12: return .morningSnack
        case 12..<15: return .lunch
        case 15..<18: return .eveningSnack
        case 18..<22: return .dinner
        default:      return .eveningSnack   // late night / very early morning
        }
    }

    /// Convenience for a concrete date in a given calendar.
    static func mealType(for date: Date, calendar: Calendar = .current) -> MealType {
        mealType(forHour: calendar.component(.hour, from: date))
    }
}
