import Foundation

/// Computed, non-persisted collections that group recipes by behaviour.
/// Each case provides a `filter` method that operates on a plain Swift array
/// so it is purely testable without a SwiftData container.
enum SystemCollection: String, CaseIterable, Identifiable, Hashable {
    case favorites
    case recentlyAdded
    case recentlyCooked
    case needsReview
    case toTry

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .favorites:     "Favorites"
        case .recentlyAdded: "Recently Added"
        case .recentlyCooked:"Recently Cooked"
        case .needsReview:   "Needs Review"
        case .toTry:         "To Try"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites:     "heart.fill"
        case .recentlyAdded: "clock.fill"
        case .recentlyCooked:"fork.knife"
        case .needsReview:   "exclamationmark.circle.fill"
        case .toTry:         "sparkles"
        }
    }

    /// Returns a filtered (and sorted, where applicable) subset of `recipes`.
    /// All property access stays on the same actor as the caller; mark the
    /// call-site `@MainActor` when referencing SwiftData @Model objects.
    func filter(_ recipes: [Recipe]) -> [Recipe] {
        switch self {
        case .favorites:
            return recipes.filter { $0.isFavorite }

        case .recentlyAdded:
            return Array(
                recipes
                    .sorted { $0.createdAt > $1.createdAt }
                    .prefix(30)
            )

        case .recentlyCooked:
            return recipes
                .filter { $0.lastCookedAt != nil }
                .sorted { ($0.lastCookedAt ?? .distantPast) > ($1.lastCookedAt ?? .distantPast) }

        case .needsReview:
            return recipes.filter { $0.needsReview }

        case .toTry:
            return recipes.filter { $0.timesCooked == 0 && !$0.needsReview }
        }
    }
}
