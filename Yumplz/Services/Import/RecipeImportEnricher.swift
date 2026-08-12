import Foundation

/// Fills gaps in LLM output: estimated quantities, cuisine, timing, dietary tags.
enum RecipeImportEnricher {

    static func enrich(_ dto: ParsedRecipeDTO, context: RecipeImportContext) -> ParsedRecipeDTO {
        var copy = dto
        copy.ingredients = dto.ingredients.map { enrichIngredient($0, source: context.cleanedText) }
        copy.cuisine = enrichCuisine(dto.cuisine, title: copy.title, context: context)
        copy.prepTimeMinutes = enrichPrepMinutes(dto.prepTimeMinutes, steps: copy.steps)
        copy.cookTimeMinutes = enrichCookMinutes(dto.cookTimeMinutes, steps: copy.steps)
        copy.dietaryTags = enrichDietaryTags(dto.dietaryTags, ingredients: copy.ingredients)
        return copy
    }

    // MARK: - Ingredients

    private static func enrichIngredient(
        _ ing: ParsedRecipeDTO.ParsedIngredientDTO,
        source: String
    ) -> ParsedRecipeDTO.ParsedIngredientDTO {
        var copy = ing

        if copy.quantity == nil, let parsed = parseQuantityFromSource(name: copy.name, source: source) {
            copy.quantity = parsed.quantity
            copy.unit = copy.unit ?? parsed.unit
        }

        copy.originalText = IngredientDisplayFormatter.normalizedOriginalText(for: copy)
        return copy
    }

    static func parseQuantityFromSource(name: String, source: String) -> (quantity: Double, unit: String?)? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 3 else { return nil }

        let escaped = NSRegularExpression.escapedPattern(for: trimmedName)
        let pattern = #"(\d+(?:\.\d+)?)\s*(tsp|tbsp|teaspoon|teaspoons|tablespoon|tablespoons|cups?|g|kg|oz|lb|cloves?|pieces?)?\s+\#(escaped)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let qtyRange = Range(match.range(at: 1), in: source),
              let qty = Double(source[qtyRange]) else { return nil }

        var unit: String?
        if match.numberOfRanges > 2, let unitRange = Range(match.range(at: 2), in: source) {
            unit = String(source[unitRange])
        }
        return (qty, unit)
    }

    // MARK: - Metadata

    private static func enrichCuisine(
        _ cuisine: String?,
        title: String,
        context: RecipeImportContext
    ) -> String? {
        if let cuisine, !cuisine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cuisine
        }

        let haystack = [
            title,
            context.videoTitle ?? "",
            context.cleanedText,
        ].joined(separator: " ").lowercased()

        let rules: [(keywords: [String], label: String)] = [
            (["rasam", "sambar", "dosa", "idli", "tamil", "andhra"], "South Indian"),
            (["curry", "biryani", "paneer", "dal ", "chana"], "Indian"),
            (["pasta", "risotto", "carbonara", "pesto"], "Italian"),
            (["taco", "salsa", "burrito", "enchilada"], "Mexican"),
            (["stir fry", "wok", "dim sum", "soy sauce"], "Chinese"),
            (["sushi", "ramen", "miso", "teriyaki"], "Japanese"),
            (["thai", "pad thai", "lemongrass"], "Thai"),
        ]

        for rule in rules where rule.keywords.contains(where: { haystack.contains($0) }) {
            return rule.label
        }
        return nil
    }

    private static func enrichPrepMinutes(_ prep: Int?, steps: [ParsedRecipeDTO.ParsedStepDTO]) -> Int? {
        if let prep, prep > 0 { return prep }
        return steps.isEmpty ? nil : 10
    }

    private static func enrichCookMinutes(
        _ cook: Int?,
        steps: [ParsedRecipeDTO.ParsedStepDTO]
    ) -> Int? {
        if let cook, cook > 0 { return cook }
        let timerTotal = steps.compactMap(\.timerSeconds).reduce(0, +)
        if timerTotal > 0 { return max(1, timerTotal / 60) }
        return steps.isEmpty ? nil : 20
    }

    private static func enrichDietaryTags(
        _ existing: [String],
        ingredients: [ParsedRecipeDTO.ParsedIngredientDTO]
    ) -> [String] {
        var tags = existing
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let blob = ingredients
            .flatMap { [$0.name, $0.originalText] }
            .joined(separator: " ")
            .lowercased()

        let meat = ["chicken", "beef", "pork", "lamb", "mutton", "fish", "salmon", "shrimp", "prawn", "bacon", "sausage", "turkey", "duck"]
        let dairy = ["milk", "cream", "butter", "ghee", "cheese", "yogurt", "paneer"]
        let eggs = ["egg", "eggs"]
        let gluten = ["flour", "bread", "pasta", "noodle", "wheat", "semolina"]

        let hasMeat = meat.contains { blob.contains($0) }
        let hasDairy = dairy.contains { blob.contains($0) }
        let hasEgg = eggs.contains { wordMatches(blob, word: $0) }
        let hasGluten = gluten.contains { blob.contains($0) }

        appendTag("Vegetarian", if: !hasMeat, to: &tags)
        appendTag("Vegan", if: !hasMeat && !hasDairy && !hasEgg, to: &tags)
        appendTag("Dairy-Free", if: !hasDairy, to: &tags)
        appendTag("Gluten-Free", if: !hasGluten, to: &tags)

        return tags
    }

    private static func wordMatches(_ text: String, word: String) -> Bool {
        text.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: word))\b"#, options: .regularExpression) != nil
    }

    private static func appendTag(_ tag: String, if condition: Bool, to tags: inout [String]) {
        guard condition else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        tags.append(tag)
    }
}
