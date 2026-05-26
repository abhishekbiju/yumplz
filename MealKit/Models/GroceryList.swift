import Foundation
import SwiftData

/// A snapshot of ingredients needed for a date range of the Meal Plan, plus any
/// items the user added manually. See `Grocery List` in CONTEXT.md.
///
/// Edits to a Grocery List do NOT propagate back to the Meal Plan or Recipes —
/// the list is downstream-only.
@Model
final class GroceryList {
    var id: UUID = UUID()

    /// Display name, defaults to the source date range ("May 24 – May 30")
    /// but is user-editable.
    var name: String = ""

    var startDate: Date?
    var endDate: Date?

    var createdAt: Date = Date()
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.list)
    var items: [GroceryItem]? = []

    init(name: String, startDate: Date? = nil, endDate: Date? = nil) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}
