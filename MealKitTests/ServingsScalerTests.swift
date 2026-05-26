import XCTest
import SwiftData
@testable import MealKit

/// TDD slices for `ServingsScaler` — red → green, one behaviour at a time.
@MainActor
final class ServingsScalerTests: XCTestCase {

    private let scaler = ServingsScaler()

    // Shared in-memory SwiftData container so `@Model` objects behave correctly.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, Recipe.self, Ingredient.self, Step.self,
            RecipeCollection.self, PlannedMeal.self, GroceryList.self, GroceryItem.self,
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    // MARK: – Slice 1 · scaledQuantity scales proportionally

    func testScaledQuantityScalesCorrectly() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let recipe = Recipe(title: "Bread")
        recipe.servings = 4
        context.insert(recipe)

        let ingredient = Ingredient(originalText: "500 g bread flour")
        ingredient.parsedQuantity = 500
        ingredient.recipe = recipe
        context.insert(ingredient)

        let result = try XCTUnwrap(scaler.scaledQuantity(ingredient: ingredient, from: 4, to: 2))
        XCTAssertEqual(result, 250, accuracy: 0.001)
    }

    // MARK: – Slice 2 · scaledQuantity returns nil when parsedQuantity is nil

    func testScaledQuantityReturnsNilWhenNoParsedQuantity() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let ingredient = Ingredient(originalText: "salt to taste")
        context.insert(ingredient)

        let result = scaler.scaledQuantity(ingredient: ingredient, from: 4, to: 2)
        XCTAssertNil(result)
    }

    // MARK: – Slice 3 · displayText falls back to originalText when no structured parse

    func testDisplayTextFallsBackToOriginalTextWhenNoStructuredParse() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let ingredient = Ingredient(originalText: "a handful of breadcrumbs")
        // parsedQuantity, parsedUnitRaw, parsedName all nil → hasStructuredParse == false
        context.insert(ingredient)

        let result = scaler.displayText(ingredient: ingredient, servings: 2, recipeServings: 4)
        XCTAssertEqual(result, "a handful of breadcrumbs")
    }

    // MARK: – Slice 4 · displayText formats ½ as a vulgar fraction

    func testDisplayTextFormatsCommonFractions() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let recipe = Recipe(title: "Cake")
        recipe.servings = 2
        context.insert(recipe)

        // 1 × (1 / 2) = 0.5 → "½"
        let ingredient = Ingredient(originalText: "1 cup flour")
        ingredient.parsedQuantity = 1
        ingredient.parsedUnit = .cup
        ingredient.parsedName = "flour"
        ingredient.recipe = recipe
        context.insert(ingredient)

        let result = scaler.displayText(ingredient: ingredient, servings: 1, recipeServings: 2)
        XCTAssertEqual(result, "½ cup flour")
    }

    // MARK: – Slice 5 · displayText omits quantity for vibe units

    func testDisplayTextOmitsQuantityForVibeUnits() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let recipe = Recipe(title: "Soup")
        recipe.servings = 1
        context.insert(recipe)

        let ingredient = Ingredient(originalText: "pinch salt")
        ingredient.parsedQuantity = 1
        ingredient.parsedUnit = .pinch
        ingredient.parsedName = "salt"
        ingredient.recipe = recipe
        context.insert(ingredient)

        let result = scaler.displayText(ingredient: ingredient, servings: 1, recipeServings: 1)
        XCTAssertEqual(result, "pinch salt")
    }

    // MARK: – Slice 6 · displayText uses parsedCustomUnit when no canonical unit

    func testDisplayTextUsesCustomUnitWhenPresent() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let recipe = Recipe(title: "Pasta")
        recipe.servings = 1
        context.insert(recipe)

        let ingredient = Ingredient(originalText: "2 knob butter")
        ingredient.parsedQuantity  = 2
        // parsedUnitRaw intentionally nil — custom unit below
        ingredient.parsedCustomUnit = "knob"
        ingredient.parsedName      = "butter"
        ingredient.recipe = recipe
        context.insert(ingredient)

        let result = scaler.displayText(ingredient: ingredient, servings: 1, recipeServings: 1)
        XCTAssertEqual(result, "2 knob butter")
    }

    // MARK: – Slice 7 · displayText rounds large quantities to 1 decimal place

    func testDisplayTextRoundsLargeQuantitiesToOneDecimal() throws {
        let container = try makeContainer()
        let context   = container.mainContext

        let recipe = Recipe(title: "Stew")
        recipe.servings = 3
        context.insert(recipe)

        // 1 × (7 / 3) = 2.333…  →  "2.3 cups"
        let ingredient = Ingredient(originalText: "1 cup")
        ingredient.parsedQuantity = 1
        ingredient.parsedUnit = .cup
        // parsedName intentionally nil — spec checks quantity+unit only
        ingredient.recipe = recipe
        context.insert(ingredient)

        let result = scaler.displayText(ingredient: ingredient, servings: 7, recipeServings: 3)
        XCTAssertEqual(result, "2.3 cups")
    }
}
