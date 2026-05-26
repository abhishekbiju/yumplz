import XCTest
import SwiftData
@testable import MealKit

final class LibraryTests: XCTestCase {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            User.self, Recipe.self, Ingredient.self, Step.self,
            RecipeCollection.self, PlannedMeal.self, GroceryList.self, GroceryItem.self,
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    // MARK: - Slice 1: SystemCollection.favorites

    @MainActor
    func testFavoritesFilterReturnsOnlyFavorites() {
        let fav = Recipe(title: "Fav")
        fav.isFavorite = true

        let notFav = Recipe(title: "Not Fav")
        notFav.isFavorite = false

        let results = SystemCollection.favorites.filter([fav, notFav])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Fav")
    }

    // MARK: - Slice 2: SystemCollection.recentlyAdded caps at 30

    @MainActor
    func testRecentlyAddedCapsAt30AndSortsNewestFirst() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let recipes: [Recipe] = (0..<35).map { i in
            let r = Recipe(title: "Recipe \(i)")
            r.createdAt = base.addingTimeInterval(TimeInterval(i * 60))
            return r
        }

        let results = SystemCollection.recentlyAdded.filter(recipes)

        XCTAssertEqual(results.count, 30)
        XCTAssertEqual(results.first?.title, "Recipe 34")
        XCTAssertEqual(results.last?.title, "Recipe 5")
    }

    // MARK: - Slice 3: SystemCollection.toTry excludes needsReview

    @MainActor
    func testToTryExcludesNeedsReview() {
        let eligible = Recipe(title: "To Try")
        eligible.timesCooked = 0
        eligible.needsReview = false

        let needsReviewRecipe = Recipe(title: "Needs Review")
        needsReviewRecipe.timesCooked = 0
        needsReviewRecipe.needsReview = true

        let alreadyCooked = Recipe(title: "Already Cooked")
        alreadyCooked.timesCooked = 3
        alreadyCooked.needsReview = false

        let results = SystemCollection.toTry.filter([eligible, needsReviewRecipe, alreadyCooked])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "To Try")
    }

    // MARK: - Slice 7: Favorite toggle persists

    @MainActor
    func testFavoriteTogglePersists() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let recipe = Recipe(title: "Toggle Test")
        context.insert(recipe)
        try context.save()

        recipe.isFavorite = true
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(fetched.first?.isFavorite, true)
    }

    // MARK: - Slice 8: User Collection CRUD

    @MainActor
    func testAddRecipeToCollectionPersists() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let recipe = Recipe(title: "Weeknight Pasta")
        let collection = RecipeCollection(name: "Weeknight Dinners")
        context.insert(recipe)
        context.insert(collection)
        collection.recipes?.append(recipe)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RecipeCollection>())
        XCTAssertEqual(fetched.first?.recipes?.count, 1)
        XCTAssertEqual(fetched.first?.recipes?.first?.title, "Weeknight Pasta")
    }

    @MainActor
    func testDeleteCollectionDoesNotDeleteRecipe() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let recipe = Recipe(title: "Survivor Recipe")
        let collection = RecipeCollection(name: "Temp Collection")
        context.insert(recipe)
        context.insert(collection)
        collection.recipes?.append(recipe)
        try context.save()

        context.delete(collection)
        try context.save()

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.title, "Survivor Recipe")
    }
}
