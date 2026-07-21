import Foundation

/// Educational content in Prvital is static, curated and bundled — it is general
/// information, **not** medical advice. Every Learn surface shows this note.
enum LearnDisclaimer {
    static let text = """
    This is general education, not medical advice. Diabetes care is individual — \
    always follow the plan agreed with your own healthcare team, and contact them \
    before changing how you treat lows and highs or how you dose insulin.
    """
}

/// A broad grouping used to organise Learn content.
enum LearnCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case rules
    case basics
    case food
    case highsAndLows = "highs_and_lows"
    case technology

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: return String(localized: "Rules")
        case .basics: return String(localized: "Basics")
        case .food: return String(localized: "Food & carbs")
        case .highsAndLows: return String(localized: "Highs & lows")
        case .technology: return String(localized: "Technology")
        }
    }

    var symbol: String {
        switch self {
        case .rules: return "list.number"
        case .basics: return "book.fill"
        case .food: return "fork.knife"
        case .highsAndLows: return "arrow.up.arrow.down"
        case .technology: return "sensor.tag.radiowaves.forward"
        }
    }
}

/// A concrete, actionable rule — the kind of step-by-step guidance people are
/// taught in diabetes education (for example the rule of 15 for treating a low).
struct DiabetesRule: Identifiable, Sendable {
    let id: String
    let title: String
    let tagline: String
    let symbol: String
    /// The ordered steps to follow.
    let steps: [String]
    /// A short paragraph of context beneath the steps.
    let detail: String
    /// A plain-language attribution for where the guidance comes from.
    let source: String
}

/// One titled paragraph within an article.
struct ArticleSection: Identifiable, Sendable {
    let heading: String
    let body: String
    var id: String { heading }
}

/// A short encyclopedia article built from titled sections, with sources.
struct EncyclopediaArticle: Identifiable, Sendable {
    let id: String
    let title: String
    let category: LearnCategory
    let summary: String
    let symbol: String
    let sections: [ArticleSection]
    let sources: [String]
}

/// A diabetes-friendly recipe with its per-serving carbohydrate count.
struct Recipe: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let servings: Int
    let carbsPerServingGrams: Double
    let prepMinutes: Int
    let ingredients: [String]
    let steps: [String]
    let tags: [String]
}
