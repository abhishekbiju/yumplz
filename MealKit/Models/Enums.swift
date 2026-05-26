import Foundation

/// How a Recipe entered the Library. See `Source` in CONTEXT.md.
enum SourceKind: String, Codable, CaseIterable, Sendable {
    case url
    case photo
    case video
    case manual
    case paste
    /// Recipes that came from the Content Library (House Recipes or Spoonacular-ingested).
    case contentLibrary
}

/// A named meal bucket within a day of the Meal Plan.
/// V1 ships with exactly four; the fixed set is a product decision, not a temporary cap.
enum Slot: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sun.haze"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "leaf"
        }
    }
}

/// The unit half of a Structured Parse.
/// The enum covers ~98% of recipe usage; anything else is stored via
/// `Ingredient.parsedCustomUnit`.
enum Unit: String, Codable, CaseIterable, Sendable {
    // Volume
    case tsp, tbsp, cup
    case flOz = "fl_oz"
    case ml, l
    // Weight
    case oz, lb, g, kg
    // Count
    case piece, clove, slice, bunch, can
    // Vibe (no quantity math)
    case pinch, dash, splash
    case toTaste = "to_taste"

    enum Family: Sendable {
        case volume, weight, count, vibe
    }

    var family: Family {
        switch self {
        case .tsp, .tbsp, .cup, .flOz, .ml, .l: .volume
        case .oz, .lb, .g, .kg: .weight
        case .piece, .clove, .slice, .bunch, .can: .count
        case .pinch, .dash, .splash, .toTaste: .vibe
        }
    }
}

/// The shelf section an Ingredient belongs to. Used to section the Grocery List.
enum StoreCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case produce
    case dairyEggs = "dairy_eggs"
    case meatSeafood = "meat_seafood"
    case pantry
    case bakery
    case frozen
    case beverages
    case spicesBaking = "spices_baking"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .produce: "Produce"
        case .dairyEggs: "Dairy & Eggs"
        case .meatSeafood: "Meat & Seafood"
        case .pantry: "Pantry"
        case .bakery: "Bakery"
        case .frozen: "Frozen"
        case .beverages: "Beverages"
        case .spicesBaking: "Spices & Baking"
        case .other: "Other"
        }
    }

    /// Default display order, can be overridden by the user (see `Q14` / Profile settings).
    static let defaultOrder: [StoreCategory] = [
        .produce, .meatSeafood, .dairyEggs, .bakery, .pantry,
        .spicesBaking, .frozen, .beverages, .other,
    ]
}
