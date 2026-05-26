import Foundation
import SwiftData

/// User-created named tag that groups Recipes. Maps to the `Collection` glossary
/// term in CONTEXT.md — the Swift type is named `RecipeCollection` to avoid
/// shadowing the standard library `Collection` protocol.
///
/// Membership is many-to-many. Flat (no nesting).
///
/// System Collections (Favorites, Recently Added, etc.) are NOT modeled here —
/// they are computed views over Recipes (see Q8).
@Model
final class RecipeCollection {
    var id: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0
    var createdAt: Date = Date()

    var recipes: [Recipe]? = []

    init(name: String, orderIndex: Int = 0) {
        self.name = name
        self.orderIndex = orderIndex
    }
}
