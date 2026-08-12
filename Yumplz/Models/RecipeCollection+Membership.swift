import Foundation

extension RecipeCollection {
    var recipeCount: Int { recipes?.count ?? 0 }

    /// Adds recipes that are not already in this collection.
    func addRecipes(_ candidates: [Recipe]) {
        for recipe in candidates {
            addRecipe(recipe)
        }
    }

    func addRecipe(_ recipe: Recipe) {
        if recipes?.contains(where: { $0.id == recipe.id }) == true { return }
        recipes?.append(recipe)
    }

    /// Seeds a new collection with the most recently created recipes from the library.
    static func seedNewCollection(_ collection: RecipeCollection, from library: [Recipe], limit: Int = 5) {
        let latest = library
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
        collection.addRecipes(Array(latest))
    }
}
