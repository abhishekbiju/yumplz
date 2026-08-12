import Foundation

/// Builds human-readable ingredient lines from structured parse fields.
enum IngredientDisplayFormatter {

    static func normalizedOriginalText(for ing: ParsedRecipeDTO.ParsedIngredientDTO) -> String {
        if originalTextHasQuantity(ing.originalText) {
            return ing.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parts: [String] = []
        if let quantity = ing.quantity {
            parts.append(formatQuantity(quantity))
        }
        if let unit = ing.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
            parts.append(unit)
        }
        let name = ing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            parts.append(name)
        }
        if let prep = ing.prep?.trimmingCharacters(in: .whitespacesAndNewlines), !prep.isEmpty {
            parts.append(prep)
        }

        let built = parts.joined(separator: " ")
        return built.isEmpty ? ing.originalText : built
    }

    /// Display text for a persisted ingredient at the recipe's default serving count.
    static func displayText(for ingredient: Ingredient, recipe: Recipe) -> String {
        ServingsScaler().displayText(
            ingredient: ingredient,
            servings: recipe.servings,
            recipeServings: max(1, recipe.servings)
        )
    }

    static func originalTextHasQuantity(_ text: String) -> Bool {
        text.range(of: #"\d"#, options: .regularExpression) != nil
    }

    private static func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
