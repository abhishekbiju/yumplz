import Foundation
import SwiftData

/// The atomic unit of the app. See `Recipe` in CONTEXT.md.
@Model
final class Recipe {
    var id: UUID = UUID()

    // Canonical fields
    var title: String = ""
    var summary: String?

    /// Hero image stored inline. For larger originals we switch to a CloudKit
    /// asset reference in a later iteration; small thumbs inline is fine for V1.
    var heroImageData: Data?

    var servings: Int = 1
    var prepTimeSeconds: Int?
    var cookTimeSeconds: Int?

    var totalTimeSeconds: Int? {
        switch (prepTimeSeconds, cookTimeSeconds) {
        case let (p?, c?): p + c
        case let (p?, nil): p
        case let (nil, c?): c
        case (nil, nil): nil
        }
    }

    // Classification
    var tags: [String] = []
    var cuisine: String?
    var dietaryTags: [String] = []

    // Nutrition (per-serving, estimated; see `Nutrition` in CONTEXT.md)
    var nutritionCalories: Int?
    var nutritionProteinGrams: Double?
    var nutritionCarbsGrams: Double?
    var nutritionFatGrams: Double?

    // Source / provenance (see `Source` in CONTEXT.md)
    var sourceKind: SourceKind = SourceKind.manual
    var sourceURL: URL?
    /// Human-readable source label (e.g. "TikTok · @creator", "bonappetit.com").
    var sourceLabel: String?
    var importedAt: Date?

    /// Stable hash of the source for duplicate detection (canonical URL, perceptual
    /// hash of a photo, etc.). Nil for manual entries.
    var sourceHash: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Personal Layer (see `Personal Layer` in CONTEXT.md). Lives on the Recipe
    // because the app is single-User per install.
    var userRating: Int?
    var userNotes: String?
    var isFavorite: Bool = false
    var timesCooked: Int = 0
    var lastCookedAt: Date?

    /// Needs Review — set when Import completed with low confidence in any field.
    var needsReview: Bool = false

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]? = []

    @Relationship(deleteRule: .cascade, inverse: \Step.recipe)
    var steps: [Step]? = []

    @Relationship(inverse: \RecipeCollection.recipes)
    var collections: [RecipeCollection]? = []

    /// Back-reference required by CloudKit (every relationship must have an inverse).
    /// Delete rule is `.nullify`: when a Recipe is deleted, its PlannedMeal entries
    /// keep their slot/date but lose the Recipe link. The UI layer surfaces a
    /// confirmation dialog before deletion per Q16.
    @Relationship(deleteRule: .nullify, inverse: \PlannedMeal.recipe)
    var plannedMeals: [PlannedMeal]? = []

    init(title: String) {
        self.title = title
    }
}
