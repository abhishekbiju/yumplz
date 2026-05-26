import Foundation
import SwiftData
@testable import MealKit

/// Isolated in-memory SwiftData container for unit tests.
///
/// Uses a unique configuration label so it never collides with the app’s
/// on-disk `MealKit` store when the test host process also boots `MealKitApp`.
enum TestModelContainer {
    @MainActor
    static func make() throws -> ModelContainer {
        let schema = Schema([
            User.self, Recipe.self, Ingredient.self, Step.self,
            RecipeCollection.self, PlannedMeal.self, GroceryList.self, GroceryItem.self,
        ])
        let config = ModelConfiguration(
            "MealKitTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
