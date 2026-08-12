import Foundation
import SwiftData

/// A single entry in a Slot of the Meal Plan. See `Meal Plan`, `Slot`,
/// `Planned Meal`, and `Planned Servings` in CONTEXT.md.
///
/// The Meal Plan itself is not modeled as a separate entity — it's the set of
/// all PlannedMeals for the current User, queried by date range.
@Model
final class PlannedMeal {
    var id: UUID = UUID()

    /// Day of the plan, normalized to start-of-day in the User's current timezone.
    var date: Date = Date()

    var slot: Slot = Slot.dinner

    /// Ordering within the same Slot on the same day.
    var orderIndex: Int = 0

    // ── Two variants: Recipe-backed or Note-only ──
    // Exactly one of `recipe` / `noteText` is meaningful.

    var recipe: Recipe?

    /// For Note-only Planned Meals ("leftovers", "takeout"). Does NOT
    /// contribute to Grocery List Aggregation.
    var noteText: String?

    /// Overrides the Recipe's own servings for Grocery List math. Nil = use
    /// the Recipe's default. Ignored when noteText is set.
    var plannedServings: Int?

    /// "Cooked" check-off. Marking true increments the Recipe's Personal
    /// Layer `timesCooked` and updates `lastCookedAt`.
    var isCooked: Bool = false
    var cookedAt: Date?

    var createdAt: Date = Date()

    init(date: Date, slot: Slot, recipe: Recipe? = nil, noteText: String? = nil) {
        self.date = date
        self.slot = slot
        self.recipe = recipe
        self.noteText = noteText
    }

    /// True for the Note-only variant.
    var isNoteOnly: Bool { recipe == nil && noteText != nil }
}
