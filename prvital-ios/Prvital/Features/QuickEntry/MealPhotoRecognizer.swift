import Foundation
#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit
#endif

/// On-device food recognition for meal photos, built on Vision's built-in
/// image classifier — no network, no cloud, nothing leaves the phone. The
/// classifier speaks its whole 1300-class taxonomy, so results are filtered
/// to a curated food vocabulary before they reach the UI.
enum MealPhotoRecognizer {

    struct Suggestion: Identifiable, Equatable, Sendable {
        /// The classifier's identifier, e.g. "pizza" or "ice_cream".
        let identifier: String
        let confidence: Double
        var id: String { identifier }
        /// "ice_cream" → "Ice cream".
        var displayName: String {
            let name = identifier.replacingOccurrences(of: "_", with: " ")
            return name.prefix(1).uppercased() + name.dropFirst()
        }
    }

    /// Identifiers we accept from the classifier — the common-food subset of
    /// Vision's taxonomy. An identifier not in this set is simply not shown,
    /// so taxonomy drift degrades gracefully.
    static let foodIdentifiers: Set<String> = [
        "apple", "banana", "orange", "grape", "strawberry", "blueberry",
        "raspberry", "watermelon", "melon", "pineapple", "mango", "peach",
        "pear", "cherry", "lemon", "kiwi", "fig", "avocado", "tomato",
        "potato", "carrot", "broccoli", "cauliflower", "cucumber", "pepper",
        "mushroom", "corn", "pumpkin", "salad", "soup", "sandwich",
        "hamburger", "cheeseburger", "hot_dog", "pizza", "pasta", "spaghetti",
        "noodle", "ramen", "sushi", "taco", "burrito", "quesadilla", "nachos",
        "rice", "fried_rice", "bread", "toast", "croissant", "bagel",
        "muffin", "doughnut", "pretzel", "pancake", "waffle", "crepe",
        "cake", "cupcake", "cookie", "brownie", "chocolate", "candy",
        "ice_cream", "yogurt", "cheese", "egg", "omelette", "bacon",
        "sausage", "steak", "chicken", "fish", "salmon", "tuna", "shrimp",
        "lobster", "french_fries", "fries", "popcorn", "chips", "cereal",
        "oatmeal", "porridge", "granola", "honey", "jam", "milk", "coffee",
        "espresso", "cappuccino", "latte", "tea", "juice", "smoothie",
        "soda", "beer", "wine", "guacamole", "hummus", "falafel", "kebab",
        "curry", "dumpling", "spring_roll", "pho", "paella", "lasagna",
        "risotto", "quiche", "pie", "tart", "apple_pie", "meatball", "tofu",
        "stew", "pastry", "baguette", "cheesecake", "tiramisu", "pudding",
    ]

    /// Classifies the photo and returns up to three confident food matches,
    /// best first. Runs the model off the main thread; returns [] on any
    /// failure — a missing suggestion is never an error the user sees.
    static func recognizeFood(in data: Data) async -> [Suggestion] {
        #if canImport(Vision) && canImport(UIKit)
        guard let cgImage = UIImage(data: data)?.cgImage else { return [] }
        let task = Task.detached(priority: .userInitiated) { () -> [Suggestion] in
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            guard (try? handler.perform([request])) != nil else { return [] }
            return (request.results ?? [])
                .filter { $0.confidence >= 0.3 && foodIdentifiers.contains($0.identifier) }
                .sorted { $0.confidence > $1.confidence }
                .prefix(3)
                .map { Suggestion(identifier: $0.identifier, confidence: Double($0.confidence)) }
        }
        return await task.value
        #else
        return []
        #endif
    }
}
