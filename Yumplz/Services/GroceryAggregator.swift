import Foundation
import SwiftData

struct AggregatedItem {
    var name: String
    var quantity: Double?
    var unit: Unit?
    var customUnit: String?
    var storeCategory: StoreCategory
}

struct GroceryAggregator {

    @MainActor
    static func aggregate(meals: [(meal: PlannedMeal, recipe: Recipe?)]) -> [AggregatedItem] {
        struct GroupKey: Hashable {
            let name: String
            let unitRaw: String  // "__nil__" when no unit
        }

        struct GroupEntry {
            var name: String
            var unit: Unit?
            var customUnit: String?
            var quantity: Double
            var storeCategory: StoreCategory
            var isVibe: Bool
        }

        var groups: [GroupKey: GroupEntry] = [:]
        var keyOrder: [GroupKey] = []

        for (meal, recipe) in meals {
            guard let recipe = recipe, !meal.isNoteOnly else { continue }

            let plannedServings = Double(meal.plannedServings ?? recipe.servings)
            let recipeServings = Double(max(1, recipe.servings))
            let scalingFactor = plannedServings / recipeServings

            let ingredients = recipe.ingredients ?? []
            for ingredient in ingredients {
                let rawName = ingredient.parsedName ?? ingredient.originalText
                let normalizedName = rawName
                    .lowercased()
                    .trimmingCharacters(in: .whitespaces)

                let unit = ingredient.parsedUnit
                let isVibe = unit?.family == .vibe
                let unitRaw = unit?.rawValue ?? "__nil__"
                let key = GroupKey(name: normalizedName, unitRaw: unitRaw)

                let scaledQty = (ingredient.parsedQuantity ?? 1.0) * scalingFactor
                let storeCat = ingredient.storeCategory ?? .other

                if groups[key] != nil {
                    if !isVibe {
                        groups[key]!.quantity += scaledQty
                    }
                } else {
                    let entry = GroupEntry(
                        name: normalizedName,
                        unit: unit,
                        customUnit: ingredient.parsedCustomUnit,
                        quantity: isVibe ? 0 : scaledQty,
                        storeCategory: storeCat,
                        isVibe: isVibe
                    )
                    groups[key] = entry
                    keyOrder.append(key)
                }
            }
        }

        return keyOrder.compactMap { key -> AggregatedItem? in
            guard let entry = groups[key] else { return nil }
            return AggregatedItem(
                name: entry.name,
                quantity: entry.isVibe ? nil : entry.quantity,
                unit: entry.unit,
                customUnit: entry.customUnit,
                storeCategory: entry.storeCategory
            )
        }
    }
}
