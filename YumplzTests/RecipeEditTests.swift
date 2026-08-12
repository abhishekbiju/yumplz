import XCTest
import SwiftData
@testable import Yumplz

/// TDD slices for the Recipe editing save path.
///
/// These tests exercise the SwiftData persistence layer directly,
/// mirroring the `save()` logic in `RecipeEditView`.
@MainActor
final class RecipeEditTests: XCTestCase {

    // MARK: – Slice 1 · saving a title change persists it

    func testSavingTitleChangePersists() throws {
        let container = try TestModelContainer.make()
        let context   = container.mainContext

        let recipe = Recipe(title: "Old")
        context.insert(recipe)
        try context.save()

        // Simulate the save path from RecipeEditView
        recipe.title      = "New"
        recipe.updatedAt  = Date()
        try context.save()

        let descriptor = FetchDescriptor<Recipe>()
        let recipes    = try context.fetch(descriptor)
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.title, "New")
    }

    // MARK: – Slice 2 · saving a servings change persists it

    func testSavingServingsChangePersists() throws {
        let container = try TestModelContainer.make()
        let context   = container.mainContext

        let recipe = Recipe(title: "Test")
        recipe.servings = 4
        context.insert(recipe)
        try context.save()

        // Simulate "Update default servings" toggle being on
        recipe.servings   = 6
        recipe.updatedAt  = Date()
        try context.save()

        let descriptor = FetchDescriptor<Recipe>()
        let recipes    = try context.fetch(descriptor)
        XCTAssertEqual(recipes.first?.servings, 6)
    }

    // MARK: – Slice 3 · adding an ingredient persists it

    func testAddingIngredientPersists() throws {
        let container = try TestModelContainer.make()
        let context   = container.mainContext

        let recipe = Recipe(title: "Test")
        context.insert(recipe)
        try context.save()

        // Simulate inserting a new Ingredient (as RecipeEditView.save() does)
        let ingredient = Ingredient(originalText: "1 cup flour", orderIndex: 0)
        ingredient.recipe = recipe
        context.insert(ingredient)
        try context.save()

        let recipeDescriptor = FetchDescriptor<Recipe>()
        let recipes          = try context.fetch(recipeDescriptor)
        XCTAssertEqual(recipes.first?.ingredients?.count, 1)
        XCTAssertEqual(recipes.first?.ingredients?.first?.originalText, "1 cup flour")
    }

    // MARK: – Slice 4 · deleting an ingredient cascade-deletes, leaving no orphan

    func testDeletingIngredientLeavesNoOrphan() throws {
        let container = try TestModelContainer.make()
        let context   = container.mainContext

        let recipe = Recipe(title: "Test")
        context.insert(recipe)

        let ingredient = Ingredient(originalText: "1 cup flour", orderIndex: 0)
        ingredient.recipe = recipe
        context.insert(ingredient)
        try context.save()

        // Confirm the ingredient is present
        let before = try context.fetch(FetchDescriptor<Ingredient>())
        XCTAssertEqual(before.count, 1)

        // Simulate deletion (matching RecipeEditView.save() delete path)
        context.delete(ingredient)
        try context.save()

        // Recipe's ingredient list must be empty
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.first?.ingredients?.count, 0)

        // No orphan Ingredient should remain in the store
        let allIngredients = try context.fetch(FetchDescriptor<Ingredient>())
        XCTAssertEqual(allIngredients.count, 0)
    }
}
