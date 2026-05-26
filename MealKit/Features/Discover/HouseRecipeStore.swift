import Foundation

// MARK: - Discover sections

enum DiscoverSection: String, CaseIterable, Identifiable {
    case quickWeeknight = "Quick Weeknight Dinners"
    case healthyBreakfasts = "Healthy Breakfasts"
    case comfortFood = "Comfort Food"
    case aroundTheWorld = "Around the World"

    var id: String { rawValue }
}

// MARK: - HouseRecipeStore

@MainActor
@Observable
final class HouseRecipeStore {
    private(set) var recipes: [HouseRecipe] = []

    func load() {
        guard let url = Bundle.main.url(forResource: "HouseRecipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([HouseRecipe].self, from: data)
        else { return }
        recipes = loaded
    }

    // MARK: Editorial sections

    var featured: HouseRecipe? {
        recipes.first(where: { $0.tags.contains("featured") })
    }

    func recipes(forSection section: DiscoverSection) -> [HouseRecipe] {
        switch section {
        case .quickWeeknight:
            recipes.filter { ($0.totalTimeMinutes ?? 999) <= 30 }
        case .healthyBreakfasts:
            recipes.filter { $0.tags.contains("breakfast") }
        case .comfortFood:
            recipes.filter { $0.tags.contains("comfort") }
        case .aroundTheWorld:
            uniqueByCuisine(recipes)
        }
    }

    func filtered(cuisine: String?, dietaryTag: String?) -> [HouseRecipe] {
        recipes.filter { recipe in
            let cuisineMatch = cuisine.map { recipe.cuisine == $0 } ?? true
            let tagMatch = dietaryTag.map { recipe.dietaryTags.contains($0) } ?? true
            return cuisineMatch && tagMatch
        }
    }

    // MARK: Computed chip values

    var allCuisines: [String] {
        var seen = Set<String>()
        return recipes.compactMap { $0.cuisine }.filter { seen.insert($0).inserted }
    }

    var allDietaryTags: [String] {
        var seen = Set<String>()
        return recipes.flatMap { $0.dietaryTags }.filter { seen.insert($0).inserted }
    }

    // MARK: Private helpers

    private func uniqueByCuisine(_ list: [HouseRecipe]) -> [HouseRecipe] {
        var seen = Set<String>()
        return list.filter { r in
            guard let c = r.cuisine else { return false }
            return seen.insert(c).inserted
        }
    }
}
