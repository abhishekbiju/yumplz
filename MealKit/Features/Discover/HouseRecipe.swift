import Foundation

/// A read-only recipe bundled with the app. Schema matches ParsedRecipeDTO
/// so the same decoder is reused. NOT stored in SwiftData — only user-saved
/// copies enter the personal Library.
struct HouseRecipe: Identifiable, Decodable, Sendable {
    let id: String          // stable string slug e.g. "spaghetti-carbonara"
    let title: String
    let summary: String?
    let servings: Int
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let cuisine: String?
    let dietaryTags: [String]
    let tags: [String]      // includes editorial tags: "quick","comfort","breakfast","featured"
    let ingredients: [ParsedRecipeDTO.ParsedIngredientDTO]
    let steps: [ParsedRecipeDTO.ParsedStepDTO]
    let nutrition: ParsedRecipeDTO.ParsedNutritionDTO?

    var totalTimeMinutes: Int? {
        switch (prepTimeMinutes, cookTimeMinutes) {
        case let (p?, c?): p + c
        case let (p?, nil): p
        case let (nil, c?): c
        case (nil, nil): nil
        }
    }
}

// MARK: - DTO conversion

extension HouseRecipe {
    /// Converts a HouseRecipe to a ParsedRecipeDTO so it can be saved via ImportService.
    func toDTO() -> ParsedRecipeDTO {
        ParsedRecipeDTO(
            title: title,
            summary: summary,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            ingredients: ingredients,
            steps: steps,
            nutrition: nutrition,
            tags: tags,
            cuisine: cuisine,
            dietaryTags: dietaryTags
        )
    }
}
