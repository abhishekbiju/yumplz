import XCTest
@testable import MealKit

@MainActor
final class HouseRecipeStoreTests: XCTestCase {

    // Shared store loaded once per test class. Each test is read-only so sharing is safe.
    var store: HouseRecipeStore!

    override func setUp() {
        super.setUp()
        store = HouseRecipeStore()
        store.load()
    }

    // MARK: - Slice 1: Loads at least 20 recipes from bundle

    func testLoadsRecipes() {
        XCTAssertGreaterThanOrEqual(store.recipes.count, 20,
            "Expected at least 20 bundled house recipes, got \(store.recipes.count)")
    }

    // MARK: - Slice 2: Every recipe has a non-empty title

    func testAllRecipesHaveNonEmptyTitles() {
        for recipe in store.recipes {
            XCTAssertFalse(recipe.title.isEmpty,
                "Recipe with id '\(recipe.id)' has an empty title")
        }
    }

    // MARK: - Slice 3: Every recipe has >= 3 ingredients

    func testAllRecipesHaveIngredients() {
        for recipe in store.recipes {
            XCTAssertGreaterThanOrEqual(recipe.ingredients.count, 3,
                "Recipe '\(recipe.title)' has only \(recipe.ingredients.count) ingredient(s)")
        }
    }

    // MARK: - Slice 4: Every recipe has >= 3 steps

    func testAllRecipesHaveSteps() {
        for recipe in store.recipes {
            XCTAssertGreaterThanOrEqual(recipe.steps.count, 3,
                "Recipe '\(recipe.title)' has only \(recipe.steps.count) step(s)")
        }
    }

    // MARK: - Slice 5: quickWeeknight section only contains short recipes

    func testQuickSectionReturnsOnlyShortRecipes() {
        let quickRecipes = store.recipes(forSection: .quickWeeknight)
        XCTAssertFalse(quickRecipes.isEmpty, "quickWeeknight section should not be empty")
        for recipe in quickRecipes {
            let total = recipe.totalTimeMinutes ?? 0
            XCTAssertLessThanOrEqual(total, 30,
                "'\(recipe.title)' in quickWeeknight has totalTimeMinutes=\(total), expected ≤ 30")
        }
    }

    // MARK: - Slice 6: healthyBreakfasts section contains only breakfast-tagged recipes

    func testBreakfastSectionContainsBreakfastTagged() {
        let breakfastRecipes = store.recipes(forSection: .healthyBreakfasts)
        XCTAssertFalse(breakfastRecipes.isEmpty, "healthyBreakfasts section should not be empty")
        for recipe in breakfastRecipes {
            XCTAssertTrue(recipe.tags.contains("breakfast"),
                "'\(recipe.title)' in healthyBreakfasts does not have the 'breakfast' tag")
        }
    }

    // MARK: - Slice 7: A featured recipe exists

    func testFeaturedRecipeExists() {
        XCTAssertNotNil(store.featured, "Expected at least one recipe tagged 'featured'")
    }

    // MARK: - Slice 8: aroundTheWorld has no duplicate cuisines

    func testAroundTheWorldHasUniqueCuisines() {
        let worldRecipes = store.recipes(forSection: .aroundTheWorld)
        XCTAssertFalse(worldRecipes.isEmpty, "aroundTheWorld section should not be empty")

        var seenCuisines = Set<String>()
        for recipe in worldRecipes {
            guard let cuisine = recipe.cuisine else {
                XCTFail("aroundTheWorld recipe '\(recipe.title)' has no cuisine")
                continue
            }
            XCTAssertTrue(seenCuisines.insert(cuisine).inserted,
                "Duplicate cuisine '\(cuisine)' found in aroundTheWorld section (recipe: '\(recipe.title)')")
        }
    }
}
