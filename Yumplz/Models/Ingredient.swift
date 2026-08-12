import Foundation
import SwiftData

/// A single line of a Recipe's ingredient list.
/// See `Ingredient`, `Original Text`, and `Structured Parse` in CONTEXT.md.
@Model
final class Ingredient {
    var id: UUID = UUID()

    /// The verbatim string the import or user supplied. Always present, always the
    /// source of truth for display.
    var originalText: String = ""

    /// Ordering within the parent Recipe's ingredient list.
    var orderIndex: Int = 0

    // ── Structured Parse (optional) ────────────────────────────────────
    // When all parsed fields are nil, the Ingredient has no Structured
    // Parse and the Original Text is the sole representation.

    var parsedQuantity: Double?
    /// Stored as the raw value of `Unit` so unknown units (from migration or LLM
    /// drift) don't break decoding. Use `parsedUnit` computed property to access typed.
    var parsedUnitRaw: String?
    /// Escape hatch for units outside the canonical enum (e.g. "knob", "handful").
    var parsedCustomUnit: String?
    var parsedName: String?
    var parsedPrep: String?

    /// Cached Store Category. Assignment priority: Spoonacular `aisle` →
    /// LLM at import → bundled static map → user override.
    var storeCategoryRaw: String?

    var recipe: Recipe?

    init(originalText: String, orderIndex: Int = 0) {
        self.originalText = originalText
        self.orderIndex = orderIndex
    }

    var parsedUnit: Unit? {
        get { parsedUnitRaw.flatMap(Unit.init(rawValue:)) }
        set { parsedUnitRaw = newValue?.rawValue }
    }

    var storeCategory: StoreCategory? {
        get { storeCategoryRaw.flatMap(StoreCategory.init(rawValue:)) }
        set { storeCategoryRaw = newValue?.rawValue }
    }

    /// True iff at least one structured field is populated.
    var hasStructuredParse: Bool {
        parsedQuantity != nil || parsedUnitRaw != nil || parsedName != nil
    }
}
