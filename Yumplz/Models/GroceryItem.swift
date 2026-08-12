import Foundation
import SwiftData

/// A single line in a Grocery List. Produced by Aggregation or by manual entry.
/// See `Grocery List`, `Aggregation`, `Manual Item` in CONTEXT.md.
@Model
final class GroceryItem {
    var id: UUID = UUID()

    /// Normalized ingredient name ("onion", "all-purpose flour"). Display-cased
    /// in the UI.
    var name: String = ""

    var quantity: Double?
    /// Raw value of `Unit`. Stored as String so future enum additions don't
    /// break decoding.
    var unitRaw: String?
    var customUnit: String?

    var storeCategoryRaw: String = StoreCategory.other.rawValue

    var isChecked: Bool = false

    /// Distinguishes user-typed items from Aggregation-produced items.
    /// Manual items survive a merge-regeneration of the list.
    var isManual: Bool = false

    /// Per-section ordering. Within a section: unchecked alphabetical first,
    /// then checked at the bottom (Q7).
    var orderIndex: Int = 0

    var list: GroceryList?

    init(name: String, quantity: Double? = nil, unit: Unit? = nil, storeCategory: StoreCategory = .other, isManual: Bool = false) {
        self.name = name
        self.quantity = quantity
        self.unitRaw = unit?.rawValue
        self.storeCategoryRaw = storeCategory.rawValue
        self.isManual = isManual
    }

    var unit: Unit? {
        get { unitRaw.flatMap(Unit.init(rawValue:)) }
        set { unitRaw = newValue?.rawValue }
    }

    var storeCategory: StoreCategory {
        get { StoreCategory(rawValue: storeCategoryRaw) ?? .other }
        set { storeCategoryRaw = newValue.rawValue }
    }
}
