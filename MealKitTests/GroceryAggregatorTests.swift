import XCTest
import SwiftData
@testable import MealKit

final class GroceryAggregatorTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func insertRecipe(title: String, servings: Int = 4, in ctx: ModelContext) -> Recipe {
        let r = Recipe(title: title)
        r.servings = servings
        ctx.insert(r)
        return r
    }

    @MainActor
    private func addIngredient(
        to recipe: Recipe,
        name: String?,
        originalText: String = "",
        quantity: Double?,
        unit: MealKit.Unit?,
        in ctx: ModelContext
    ) {
        let text = originalText.isEmpty ? (name ?? "ingredient") : originalText
        let i = Ingredient(originalText: text, orderIndex: recipe.ingredients?.count ?? 0)
        i.parsedName = name
        i.parsedQuantity = quantity
        i.parsedUnit = unit
        i.recipe = recipe
        ctx.insert(i)
    }

    @MainActor
    private func makeMeal(
        recipe: Recipe,
        plannedServings: Int? = nil,
        slot: Slot = .dinner,
        in ctx: ModelContext
    ) -> PlannedMeal {
        let m = PlannedMeal(date: Date(), slot: slot, recipe: recipe)
        m.plannedServings = plannedServings
        ctx.insert(m)
        return m
    }

    // MARK: - Slice 1 — same ingredient from 2 meals sums quantities

    @MainActor
    func testSameIngredientSumsQuantities() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let r1 = insertRecipe(title: "R1", servings: 4, in: ctx)
        addIngredient(to: r1, name: "flour", quantity: 500, unit: .g, in: ctx)
        let meal1 = makeMeal(recipe: r1, plannedServings: 4, in: ctx)

        let r2 = insertRecipe(title: "R2", servings: 2, in: ctx)
        addIngredient(to: r2, name: "flour", quantity: 200, unit: .g, in: ctx)
        let meal2 = makeMeal(recipe: r2, plannedServings: 2, in: ctx)

        try ctx.save()

        let result = GroceryAggregator.aggregate(meals: [
            (meal: meal1, recipe: r1),
            (meal: meal2, recipe: r2),
        ])
        _ = container  // keep container alive
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "flour")
        XCTAssertEqual(result.first?.quantity, 700)
        XCTAssertEqual(result.first?.unit, .g)
    }

    // MARK: - Slice 2 — scaling by plannedServings works

    @MainActor
    func testScalingByPlannedServings() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let r = insertRecipe(title: "Cake", servings: 4, in: ctx)
        addIngredient(to: r, name: "butter", quantity: 100, unit: .g, in: ctx)
        let meal = makeMeal(recipe: r, plannedServings: 2, in: ctx)
        try ctx.save()

        let result = GroceryAggregator.aggregate(meals: [(meal: meal, recipe: r)])
        _ = container
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "butter")
        XCTAssertEqual(result.first?.quantity, 50)
        XCTAssertEqual(result.first?.unit, .g)
    }

    // MARK: - Slice 3 — same unit groups; different units produce separate rows

    @MainActor
    func testSameUnitGroupsDifferentUnitsStaySeparate() throws {
        // Part A: same unit → 1 row
        let containerA = try TestModelContainer.make()
        let ctxA = containerA.mainContext

        let rA1 = insertRecipe(title: "A1", servings: 1, in: ctxA)
        addIngredient(to: rA1, name: "milk", quantity: 200, unit: .ml, in: ctxA)
        let mealA1 = makeMeal(recipe: rA1, plannedServings: 1, in: ctxA)

        let rA2 = insertRecipe(title: "A2", servings: 1, in: ctxA)
        addIngredient(to: rA2, name: "milk", quantity: 300, unit: .ml, in: ctxA)
        let mealA2 = makeMeal(recipe: rA2, plannedServings: 1, in: ctxA)
        try ctxA.save()

        let resultA = GroceryAggregator.aggregate(meals: [
            (meal: mealA1, recipe: rA1),
            (meal: mealA2, recipe: rA2),
        ])
        _ = containerA
        let milkA = resultA.filter { $0.name == "milk" }
        XCTAssertEqual(milkA.count, 1)
        XCTAssertEqual(milkA.first?.quantity, 500)

        // Part B: different units → 2 rows
        let containerB = try TestModelContainer.make()
        let ctxB = containerB.mainContext

        let rB1 = insertRecipe(title: "B1", servings: 1, in: ctxB)
        addIngredient(to: rB1, name: "milk", quantity: 200, unit: .ml, in: ctxB)
        let mealB1 = makeMeal(recipe: rB1, plannedServings: 1, in: ctxB)

        let rB2 = insertRecipe(title: "B2", servings: 1, in: ctxB)
        addIngredient(to: rB2, name: "milk", quantity: 1, unit: .cup, in: ctxB)
        let mealB2 = makeMeal(recipe: rB2, plannedServings: 1, in: ctxB)
        try ctxB.save()

        let resultB = GroceryAggregator.aggregate(meals: [
            (meal: mealB1, recipe: rB1),
            (meal: mealB2, recipe: rB2),
        ])
        _ = containerB
        let milkB = resultB.filter { $0.name == "milk" }
        XCTAssertEqual(milkB.count, 2)
    }

    // MARK: - Slice 4 — vibe units get nil quantity

    @MainActor
    func testVibeUnitsGetNilQuantity() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let r = insertRecipe(title: "Soup", servings: 4, in: ctx)
        addIngredient(to: r, name: "salt", quantity: 2, unit: .pinch, in: ctx)
        let meal = makeMeal(recipe: r, plannedServings: 4, in: ctx)
        try ctx.save()

        let result = GroceryAggregator.aggregate(meals: [(meal: meal, recipe: r)])
        _ = container
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "salt")
        XCTAssertNil(result.first?.quantity)
        XCTAssertEqual(result.first?.unit, .pinch)
    }

    // MARK: - Slice 5 — fallback to normalised originalText when parsedName is nil

    @MainActor
    func testFallbackToOriginalText() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let r = insertRecipe(title: "Garnish", servings: 1, in: ctx)
        let i = Ingredient(originalText: " Fresh Herbs ", orderIndex: 0)
        i.parsedName = nil
        i.parsedQuantity = nil
        i.parsedUnit = nil
        i.recipe = r
        ctx.insert(i)
        let meal = makeMeal(recipe: r, plannedServings: 1, in: ctx)
        try ctx.save()

        let result = GroceryAggregator.aggregate(meals: [(meal: meal, recipe: r)])
        _ = container
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "fresh herbs")
    }

    // MARK: - Slice 6 — note-only PlannedMeals are skipped

    @MainActor
    func testNoteOnlyMealsAreSkipped() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let meal = PlannedMeal(date: Date(), slot: .lunch, noteText: "leftovers")
        ctx.insert(meal)
        try ctx.save()

        let result = GroceryAggregator.aggregate(meals: [(meal: meal, recipe: nil)])
        _ = container
        XCTAssertEqual(result.count, 0)
    }
}
