import Foundation
import SwiftData

// MARK: - Constraints

/// User-supplied parameters for a plan generation run.
struct PlanConstraints: Sendable {
    var startDate: Date
    var numberOfDays: Int                   // 1–7
    var dietaryTags: Set<String>            // e.g. "Vegetarian" — recipes must include ALL
    var includedCuisines: Set<String>       // e.g. "Italian" — recipe must match one (if non-empty)
    var excludedCuisines: Set<String>       // e.g. "Italian" — excluded
    var maxCookTimeSeconds: Int?            // nil = no limit
    var servings: Int                       // propagated to PlannedMeal.plannedServings

    static let `default` = PlanConstraints(
        startDate: Date(),
        numberOfDays: 7,
        dietaryTags: [],
        includedCuisines: [],
        excludedCuisines: [],
        maxCookTimeSeconds: nil,
        servings: 2
    )
}

// MARK: - Draft

/// An in-memory planned meal that has NOT yet been written to SwiftData.
struct DraftMeal: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let slot: Slot
    let recipeID: UUID
    let recipeTitle: String
    let plannedServings: Int

    init(date: Date, slot: Slot, recipe: Recipe, plannedServings: Int) {
        self.id = UUID()
        self.date = date
        self.slot = slot
        self.recipeID = recipe.id
        self.recipeTitle = recipe.title
        self.plannedServings = plannedServings
    }
}

// MARK: - Candidate filtering (pure, testable)

/// Pure functions that filter and rank recipe candidates.
/// No LLM or SwiftData access — fully unit-testable.
enum PlanCandidateFilter {

    /// Returns up to `limit` recipes from `pool` that satisfy `constraints`
    /// for a given `slot`. Excludes recipes already used on `excludedDates`.
    static func candidates(
        from pool: [Recipe],
        slot: Slot,
        constraints: PlanConstraints,
        alreadyUsed: Set<UUID>,
        limit: Int = 10
    ) -> [Recipe] {
        pool
            .filter { recipe in
                passesConstraints(recipe, constraints: constraints) &&
                !alreadyUsed.contains(recipe.id)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// True when a recipe satisfies all hard constraints.
    static func passesConstraints(_ recipe: Recipe, constraints: PlanConstraints) -> Bool {
        // Dietary — recipe must contain every required tag (case-insensitive)
        let required = constraints.dietaryTags.map { $0.lowercased() }
        let recipeTags = recipe.dietaryTags.map { $0.lowercased() }
        if !required.isEmpty && !required.allSatisfy({ recipeTags.contains($0) }) {
            return false
        }
        // Cuisine inclusion — when set, recipe must match at least one
        if !constraints.includedCuisines.isEmpty {
            guard let cuisine = recipe.cuisine?.lowercased(), !cuisine.isEmpty else { return false }
            let allowed = constraints.includedCuisines.map { $0.lowercased() }
            if !allowed.contains(cuisine) { return false }
        }
        // Cuisine exclusion
        if let cuisine = recipe.cuisine?.lowercased(),
           constraints.excludedCuisines.contains(where: { $0.lowercased() == cuisine }) {
            return false
        }
        // Cook time
        if let maxSec = constraints.maxCookTimeSeconds,
           let totalSec = recipe.totalTimeSeconds,
           totalSec > maxSec {
            return false
        }
        return true
    }
}

// MARK: - Local candidate selection (no LLM)

/// Picks recipes on-device for plan generation. Fast and deterministic enough
/// for interactive use; avoids multi-minute per-slot LLM calls on a 3B model.
enum PlanCandidatePicker {

    /// Chooses the best candidate for a slot, preferring cuisine variety.
    static func pickBest(
        from candidates: [Recipe],
        recentCuisines: [String]
    ) -> Recipe? {
        guard !candidates.isEmpty else { return nil }

        let recent = Set(recentCuisines.map { $0.lowercased() })
        let novel = candidates.filter { recipe in
            guard let cuisine = recipe.cuisine?.lowercased(), !cuisine.isEmpty else { return true }
            return !recent.contains(cuisine)
        }

        let pool = novel.isEmpty ? candidates : novel
        return pool.randomElement()
    }

    /// Suggests swaps when the same cuisine appears on consecutive days.
    static func varietySwaps(
        draft: [PlanDraftAssembler.SlotKey: Recipe],
        pool: [Recipe],
        constraints: PlanConstraints
    ) -> [PlanDraftAssembler.SlotKey: Recipe] {
        let calendar = Calendar.current
        let sortedKeys = draft.keys.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            let ai = Slot.allCases.firstIndex(of: $0.slot) ?? 0
            let bi = Slot.allCases.firstIndex(of: $1.slot) ?? 0
            return ai < bi
        }

        var swaps: [PlanDraftAssembler.SlotKey: Recipe] = [:]
        var usedIDs = Set(draft.values.map(\.id))

        for index in 1..<sortedKeys.count {
            let prevKey = sortedKeys[index - 1]
            let key = sortedKeys[index]
            guard let prev = draft[prevKey], let current = draft[key] else { continue }

            let prevCuisine = prev.cuisine?.lowercased()
            let currentCuisine = current.cuisine?.lowercased()
            guard let prevCuisine, let currentCuisine,
                  prevCuisine == currentCuisine,
                  !calendar.isDate(prevKey.date, inSameDayAs: key.date) else { continue }

            var excluded = usedIDs
            excluded.remove(current.id)

            let alternatives = PlanCandidateFilter.candidates(
                from: pool,
                slot: key.slot,
                constraints: constraints,
                alreadyUsed: excluded
            )
            .filter { ($0.cuisine?.lowercased() ?? "") != currentCuisine }

            if let replacement = alternatives.first {
                swaps[key] = replacement
                usedIDs.remove(current.id)
                usedIDs.insert(replacement.id)
            }
        }

        return swaps
    }
}

// MARK: - Draft assembly

/// Assembles a complete draft plan from a map of (date, slot) → Recipe.
enum PlanDraftAssembler {

    struct SlotKey: Hashable {
        let date: Date
        let slot: Slot
    }

    /// Builds `DraftMeal` list from a selection map.
    static func assemble(
        selections: [SlotKey: Recipe],
        servings: Int
    ) -> [DraftMeal] {
        selections
            .sorted { a, b in
                if a.key.date != b.key.date { return a.key.date < b.key.date }
                return Slot.allCases.firstIndex(of: a.key.slot) ?? 0 <
                       Slot.allCases.firstIndex(of: b.key.slot) ?? 0
            }
            .map { key, recipe in
                DraftMeal(date: key.date, slot: key.slot, recipe: recipe, plannedServings: servings)
            }
    }

    /// Persists a draft to SwiftData and returns the new PlannedMeal IDs.
    @MainActor
    static func commit(
        draft: [DraftMeal],
        recipeFor lookup: (UUID) -> Recipe?,
        context: ModelContext
    ) -> [PlannedMeal] {
        var result: [PlannedMeal] = []
        for d in draft {
            guard let recipe = lookup(d.recipeID) else { continue }
            let meal = PlannedMeal(date: d.date, slot: d.slot, recipe: recipe)
            meal.plannedServings = d.plannedServings
            context.insert(meal)
            result.append(meal)
        }
        try? context.save()
        return result
    }
}

// MARK: - PlanGenerationService

/// Builds a meal plan from the user's recipe library.
/// Uses fast on-device selection (cuisine diversity + constraints) so generation
/// finishes in seconds. Per-slot LLM calls were removed — they could run for
/// minutes on a 3B model and appeared as a hung spinner.
@MainActor
@Observable
final class PlanGenerationService {

    enum GenerationState {
        case idle
        case generating(step: String, progress: Double)   // 0–1
        case draft([DraftMeal])
        case failed(Error)
    }

    private(set) var state: GenerationState = .idle

    private let inference: InferenceService
    private let downloads: ModelDownloadManager

    init(inference: InferenceService, downloads: ModelDownloadManager) {
        self.inference = inference
        self.downloads = downloads
    }

    // MARK: - Generation entry point

    func generate(
        constraints: PlanConstraints,
        from pool: [Recipe],
        context: ModelContext
    ) async {
        _ = context  // reserved for future persistence hooks

        guard !pool.isEmpty else {
            state = .failed(GenerationError.noEligibleRecipes)
            return
        }

        state = .generating(step: "Preparing…", progress: 0.0)

        // Step 1 — enumerate slots
        let slots = enumerateSlots(startDate: constraints.startDate, days: constraints.numberOfDays)
        guard !slots.isEmpty else {
            state = .failed(GenerationError.noSlotsToFill)
            return
        }

        // Step 2 — pick a recipe for each slot (on-device, no LLM)
        var selections: [PlanDraftAssembler.SlotKey: Recipe] = [:]
        var usedIDs = Set<UUID>()
        var recentCuisines: [String] = []

        for (index, (date, slot)) in slots.enumerated() {
            let progress = 0.1 + 0.65 * (Double(index) / Double(slots.count))
            state = .generating(step: "Picking \(slot.displayName) · \(dayLabel(date))…", progress: progress)

            // Yield so SwiftUI can refresh the progress label between slots.
            await Task.yield()

            let key = PlanDraftAssembler.SlotKey(date: date, slot: slot)
            let candidates = PlanCandidateFilter.candidates(
                from: pool,
                slot: slot,
                constraints: constraints,
                alreadyUsed: usedIDs
            )
            guard let picked = PlanCandidatePicker.pickBest(
                from: candidates,
                recentCuisines: recentCuisines
            ) else { continue }

            selections[key] = picked
            usedIDs.insert(picked.id)
            if let cuisine = picked.cuisine {
                recentCuisines.append(cuisine)
                if recentCuisines.count > 6 { recentCuisines.removeFirst() }
            }
        }

        guard !selections.isEmpty else {
            state = .failed(GenerationError.noEligibleRecipes)
            return
        }

        // Step 3 — local variety pass (no LLM)
        state = .generating(step: "Balancing variety…", progress: 0.85)
        let swapSuggestions = PlanCandidatePicker.varietySwaps(
            draft: selections,
            pool: pool,
            constraints: constraints
        )

        for (swapKey, replacement) in swapSuggestions {
            if let current = selections[swapKey] {
                usedIDs.remove(current.id)
            }
            selections[swapKey] = replacement
            usedIDs.insert(replacement.id)
        }

        let draft = PlanDraftAssembler.assemble(selections: selections, servings: constraints.servings)
        state = .draft(draft)
    }

    // MARK: - Commit accepted draft

    func commit(draft: [DraftMeal], pool: [Recipe], context: ModelContext) {
        let recipeMap = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        _ = PlanDraftAssembler.commit(
            draft: draft,
            recipeFor: { recipeMap[$0] },
            context: context
        )
        state = .idle
    }

    func reset() { state = .idle }

    // MARK: - Private helpers

    /// Enumerate (Date, Slot) pairs for the plan period.
    func enumerateSlots(startDate: Date, days: Int) -> [(Date, Slot)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        var result: [(Date, Slot)] = []
        for dayOffset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: start) {
                for slot in Slot.allCases {
                    result.append((date, slot))
                }
            }
        }
        return result
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }
}

// MARK: - Errors

enum GenerationError: LocalizedError {
    case modelNotDownloaded
    case noSlotsToFill
    case noEligibleRecipes

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "The AI model has not been downloaded yet."
        case .noSlotsToFill:     return "No slots to fill for the selected date range."
        case .noEligibleRecipes: return "No recipes match the selected constraints."
        }
    }
}
