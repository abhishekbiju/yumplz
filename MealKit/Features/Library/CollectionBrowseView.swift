import SwiftUI

/// Shows a `RecipeGridView` filtered to the recipes belonging to a user-created
/// `RecipeCollection`. Navigation to `RecipeDetailView` is handled by
/// `RecipeGridView`'s own `navigationDestination`.
struct CollectionBrowseView: View {
    let collection: RecipeCollection

    var body: some View {
        RecipeGridView(recipes: collection.recipes ?? [])
            .navigationTitle(collection.name)
    }
}

#Preview {
    let collection = RecipeCollection(name: "Weeknight Dinners")
    let r1 = Recipe(title: "Pasta e Fagioli")
    r1.cookTimeSeconds = 30 * 60
    r1.cuisine = "Italian"
    collection.recipes = [r1]

    return NavigationStack {
        CollectionBrowseView(collection: collection)
    }
    .modelContainer(for: [Recipe.self, RecipeCollection.self], inMemory: true)
}
