import Foundation
import Observation

@MainActor
@Observable
final class LibrarySearchViewModel {
    var query: String = ""
    var selectedDietaryTags: Set<String> = []
    var maxCookTimeSeconds: Int? = nil

    func filter(_ recipes: [Recipe]) -> [Recipe] {
        var result = recipes

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let q = trimmed.lowercased()
            result = result.filter { r in
                r.title.lowercased().contains(q)
                    || (r.cuisine ?? "").lowercased().contains(q)
                    || r.tags.joined(separator: " ").lowercased().contains(q)
                    || r.dietaryTags.joined(separator: " ").lowercased().contains(q)
                    || (r.summary ?? "").lowercased().contains(q)
            }
        }

        if !selectedDietaryTags.isEmpty {
            result = result.filter { r in
                selectedDietaryTags.allSatisfy { r.dietaryTags.contains($0) }
            }
        }

        if let max = maxCookTimeSeconds {
            result = result.filter { r in
                (r.totalTimeSeconds ?? Int.max) <= max
            }
        }

        return result
    }

    var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
            || !selectedDietaryTags.isEmpty
            || maxCookTimeSeconds != nil
    }

    func clearAll() {
        query = ""
        selectedDietaryTags = []
        maxCookTimeSeconds = nil
    }
}
