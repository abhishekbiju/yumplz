import XCTest
import SwiftData
@testable import MealKit

/// Tests for `IngredientEmojiMapper`.
///
/// Each slice follows RED→GREEN: the test documents a specific mapping behavior
/// and the mapper implementation makes it green.
final class IngredientEmojiMapperTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal `Ingredient` in an isolated in-memory store.
    /// Returns both the ingredient and the container so the container stays alive
    /// (SwiftData objects are invalid after their container is deallocated).
    @MainActor
    private func makeIngredient(
        originalText: String = "ingredient",
        parsedName: String? = nil,
        storeCategory: StoreCategory? = nil
    ) throws -> (ingredient: Ingredient, container: ModelContainer) {
        let container = try TestModelContainer.make()
        let ingredient = Ingredient(originalText: originalText)
        ingredient.parsedName = parsedName
        ingredient.storeCategory = storeCategory
        container.mainContext.insert(ingredient)
        return (ingredient, container)
    }

    // MARK: - Slice 1 — garlic → 🧄

    @MainActor
    func testGarlicReturnsGarlicEmoji() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "3 cloves garlic",
            parsedName: "garlic"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🧄")
        _ = container
    }

    // MARK: - Slice 2 — "chicken breast" contains "chicken" → 🍗

    @MainActor
    func testChickenBreastReturnsChickenEmoji() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "500 g chicken breast",
            parsedName: "chicken breast"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🍗")
        _ = container
    }

    // MARK: - Slice 3 — salmon → 🐟

    @MainActor
    func testSalmonReturnsFishEmoji() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "2 fillets salmon",
            parsedName: "salmon"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🐟")
        _ = container
    }

    // MARK: - Slice 4 — "all-purpose flour" contains "flour" → 🌾

    @MainActor
    func testFlourReturnsGrainEmoji() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "2 cups all-purpose flour",
            parsedName: "all-purpose flour"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🌾")
        _ = container
    }

    // MARK: - Slice 5 — "eggs" contains "egg" → 🥚

    @MainActor
    func testEggReturnsEggEmoji() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "2 large eggs",
            parsedName: "eggs"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🥚")
        _ = container
    }

    // MARK: - Slice 6 — no parsedName, category Produce → 🥬

    @MainActor
    func testCategoryFallbackProduce() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "seasonal greens",
            parsedName: nil,
            storeCategory: .produce
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🥬")
        _ = container
    }

    // MARK: - Slice 7 — no parsedName, category Dairy & Eggs → 🥛

    @MainActor
    func testCategoryFallbackDairy() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "dairy product",
            parsedName: nil,
            storeCategory: .dairyEggs
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🥛")
        _ = container
    }

    // MARK: - Slice 8 — unknown parsedName falls back to category emoji

    @MainActor
    func testUnknownIngredientFallsBackToCategory() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "fresh durian",
            parsedName: "durian",
            storeCategory: .produce
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🥬")
        _ = container
    }

    // MARK: - Bonus slices

    // "bell pepper" should prefer the longer keyword match → 🫑
    @MainActor
    func testBellPepperMatchesBellPepper() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "1 red bell pepper",
            parsedName: "bell pepper"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🫑")
        _ = container
    }

    // "peanut butter" → 🥜
    @MainActor
    func testPeanutButterReturnsPeanutEmoji() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "2 tbsp peanut butter",
            parsedName: "peanut butter"
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🥜")
        _ = container
    }

    // Keyword match on originalText when parsedName is nil
    @MainActor
    func testOriginalTextFallback() throws {
        let (ingredient, container) = try makeIngredient(
            originalText: "2 large eggs, beaten",
            parsedName: nil,
            storeCategory: .dairyEggs
        )
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: ingredient), "🥚")
        _ = container
    }

    // GroceryItem emoji resolution by name
    @MainActor
    func testGroceryItemEmojiByName() throws {
        let container = try TestModelContainer.make()
        let item = GroceryItem(name: "salmon", storeCategory: .meatSeafood)
        container.mainContext.insert(item)
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: item), "🐟")
        _ = container
    }

    // GroceryItem falls back to category when name is not in table
    @MainActor
    func testGroceryItemCategoryFallback() throws {
        let container = try TestModelContainer.make()
        let item = GroceryItem(name: "durian", storeCategory: .produce)
        container.mainContext.insert(item)
        XCTAssertEqual(IngredientEmojiMapper.emoji(for: item), "🥬")
        _ = container
    }
}
