import XCTest
import SwiftData
@testable import MealKit

/// Sanity smoke test for the SwiftData model layer. The serious test coverage
/// lives in the algorithm-heavy modules (import parser, Aggregation, scaling
/// math) once they exist.
final class ModelSmokeTests: XCTestCase {

    @MainActor
    func testInMemoryContainerInitializes() throws {
        let schema = Schema([
            User.self, Recipe.self, Ingredient.self, Step.self,
            RecipeCollection.self, PlannedMeal.self, GroceryList.self, GroceryItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        XCTAssertNotNil(container)
    }

    @MainActor
    func testRecipeWithIngredientsAndSteps() throws {
        let schema = Schema([
            User.self, Recipe.self, Ingredient.self, Step.self,
            RecipeCollection.self, PlannedMeal.self, GroceryList.self, GroceryItem.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let recipe = Recipe(title: "Sourdough Focaccia")
        recipe.servings = 6
        recipe.cookTimeSeconds = 25 * 60

        let flour = Ingredient(originalText: "500 g bread flour", orderIndex: 0)
        flour.parsedQuantity = 500
        flour.parsedUnit = .g
        flour.parsedName = "bread flour"
        flour.recipe = recipe

        let salt = Ingredient(originalText: "10 g salt", orderIndex: 1)
        salt.parsedQuantity = 10
        salt.parsedUnit = .g
        salt.parsedName = "salt"
        salt.recipe = recipe

        let step1 = Step(text: "Mix flour and water.", orderIndex: 0)
        step1.recipe = recipe

        let step2 = Step(text: "Bake.", orderIndex: 1, timerSeconds: 25 * 60)
        step2.recipe = recipe

        context.insert(recipe)
        try context.save()

        let descriptor = FetchDescriptor<Recipe>()
        let recipes = try context.fetch(descriptor)
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.ingredients?.count, 2)
        XCTAssertEqual(recipes.first?.steps?.count, 2)
        XCTAssertEqual(recipes.first?.totalTimeSeconds, 25 * 60)
    }

    func testUnitFamilies() {
        XCTAssertEqual(Unit.cup.family, .volume)
        XCTAssertEqual(Unit.g.family, .weight)
        XCTAssertEqual(Unit.piece.family, .count)
        XCTAssertEqual(Unit.pinch.family, .vibe)
    }

    func testStoreCategoryDefaultOrderCoversAllCases() {
        XCTAssertEqual(Set(StoreCategory.defaultOrder), Set(StoreCategory.allCases))
        XCTAssertEqual(StoreCategory.defaultOrder.count, StoreCategory.allCases.count)
    }
}
