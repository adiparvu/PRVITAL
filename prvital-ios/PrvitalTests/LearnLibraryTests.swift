import XCTest
@testable import Prvital

final class LearnLibraryTests: XCTestCase {

    func testContentIsPresent() {
        XCTAssertFalse(LearnLibrary.rules.isEmpty)
        XCTAssertFalse(LearnLibrary.articles.isEmpty)
        XCTAssertFalse(LearnLibrary.recipes.isEmpty)
    }

    func testRuleIDsAreUnique() {
        let ids = LearnLibrary.rules.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testArticleIDsAreUnique() {
        let ids = LearnLibrary.articles.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRecipeIDsAreUnique() {
        let ids = LearnLibrary.recipes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testRulesHaveSteps() {
        for rule in LearnLibrary.rules {
            XCTAssertFalse(rule.steps.isEmpty, "\(rule.id) has no steps")
            XCTAssertFalse(rule.title.isEmpty)
        }
    }

    func testArticlesHaveSections() {
        for article in LearnLibrary.articles {
            XCTAssertFalse(article.sections.isEmpty, "\(article.id) has no sections")
            XCTAssertFalse(article.sources.isEmpty, "\(article.id) has no sources")
        }
    }

    func testRecipesHaveSaneCarbs() {
        for recipe in LearnLibrary.recipes {
            XCTAssertGreaterThan(recipe.servings, 0)
            XCTAssertGreaterThanOrEqual(recipe.carbsPerServingGrams, 0)
            XCTAssertLessThan(recipe.carbsPerServingGrams, 200, "\(recipe.id) carbs look wrong")
            XCTAssertFalse(recipe.ingredients.isEmpty)
            XCTAssertFalse(recipe.steps.isEmpty)
        }
    }

    func testDisclaimerPresent() {
        XCTAssertFalse(LearnDisclaimer.text.isEmpty)
    }
}
