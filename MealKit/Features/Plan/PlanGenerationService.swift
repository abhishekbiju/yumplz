import Foundation
import SwiftData

// MARK: - Constraints

/// User-supplied parameters for a plan generation run.
struct PlanConstraints: Sendable {
    var startDate: Date
    var numberOfDays: Int                   // 1–7
    var dietaryTags: Set<String>            // e.g. "Vegetarian" — recipes must include ALL
    var excludedCuisines: Set<String>       // e.g. "Italian" — excluded
    var maxCookTimeSeconds: Int?            // nil = no limit
    var servings: Int                       // propagated to PlannedMeal.plannedServings

    static let `default` = PlanConstraints(
        startDate: Date(),
        numberOfDays: 7,
        dietaryTags: [],
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

/// Orchestrates the four-step decomposed LLM plan generation (ADR 0004).
/// - Step 1: enumerate (date, slot) pairs
/// - Step 2: for each slot, pick a candidate via LLM or random fallback
/// - Step 3: variety check via LLM (optional, falls back to no-op)
/// - Step 4: apply swaps for flagged slots
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
        state = .generating(step: "Preparing…", progress: 0.0)

        // Ensure LLM is loaded
        let modelURL = ModelDownloadManager.modelsDirectory
            .appendingPathComponent(LocalModel.llama3_2_3b.rawValue)
        guard (try? modelURL.checkResourceIsReachable()) == true else {
            state = .failed(GenerationError.modelNotDownloaded)
            return
        }

        if case .ready = inference.state {} else {
            do {
                try await inference.load(modelURL: modelURL)
            } catch {
                state = .failed(error)
                return
            }
        }

        // Step 1 — enumerate slots
        let slots = enumerateSlots(startDate: constraints.startDate, days: constraints.numberOfDays)
        guard !slots.isEmpty else {
            state = .failed(GenerationError.noSlotsToFill)
            return
        }

        // Step 2 — pick a recipe for each slot
        var selections: [PlanDraftAssembler.SlotKey: Recipe] = [:]
        var usedIDs = Set<UUID>()

        for (index, (date, slot)) in slots.enumerated() {
            let progress = 0.1 + 0.6 * (Double(index) / Double(slots.count))
            state = .generating(step: "Picking \(slot.displayName) · \(dayLabel(date))…", progress: progress)

            let key = PlanDraftAssembler.SlotKey(date: date, slot: slot)
            let candidates = PlanCandidateFilter.candidates(
                from: pool,
                slot: slot,
                constraints: constraints,
                alreadyUsed: usedIDs
            )
            guard !candidates.isEmpty else { continue }

            let picked = await pickViaLLM(
                candidates: candidates,
                date: date,
                slot: slot,
                constraints: constraints
            ) ?? candidates.randomElement()!

            selections[key] = picked
            usedIDs.insert(picked.id)
        }

        // Step 3 — variety check
        state = .generating(step: "Checking variety…", progress: 0.75)
        let swapSuggestions = await runVarietyCheck(draft: selections, pool: pool, constraints: constraints)

        // Step 4 — apply swaps
        state = .generating(step: "Refining plan…", progress: 0.9)
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

    /// Ask the LLM to pick from a candidate list. Returns nil on failure
    /// (caller falls back to random selection).
    private func pickViaLLM(
        candidates: [Recipe],
        date: Date,
        slot: Slot,
        constraints: PlanConstraints
    ) async -> Recipe? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: date)

        struct CandidateDTO: Encodable {
            let id: String
            let title: String
            let cuisine: String
            let dietaryTags: [String]
            let totalTimeSeconds: Int
        }

        let dtos = candidates.map { r in
            CandidateDTO(
                id: r.id.uuidString,
                title: r.title,
                cuisine: r.cuisine ?? "General",
                dietaryTags: r.dietaryTags,
                totalTimeSeconds: r.totalTimeSeconds ?? 0
            )
        }
        guard let json = try? JSONEncoder().encode(dtos),
              let jsonStr = String(data: json, encoding: .utf8) else { return nil }

        let constraintStr = describeConstraints(constraints)
        let prompt = RecipePrompts.planCandidatePickPrompt(
            date: dateStr,
            slot: slot.displayName,
            constraints: constraintStr,
            candidatesJSON: jsonStr
        )

        guard let raw = try? await inference.complete(prompt: prompt, maxNewTokens: 128),
              let extracted = raw.extractedJSON(),
              let data = extracted.data(using: .utf8) else { return nil }

        struct PickDTO: Decodable { let selectedId: String }
        guard let pick = try? JSONDecoder().decode(PickDTO.self, from: data),
              let uuid = UUID(uuidString: pick.selectedId) else { return nil }

        return candidates.first(where: { $0.id == uuid })
    }

    /// Ask the LLM to review the full draft for variety problems.
    private func runVarietyCheck(
        draft: [PlanDraftAssembler.SlotKey: Recipe],
        pool: [Recipe],
        constraints: PlanConstraints
    ) async -> [PlanDraftAssembler.SlotKey: Recipe] {
        struct DraftDTO: Encodable {
            let date: String
            let slot: String
            let title: String
            let cuisine: String
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dtos = draft.map { key, recipe in
            DraftDTO(
                date: formatter.string(from: key.date),
                slot: key.slot.displayName,
                title: recipe.title,
                cuisine: recipe.cuisine ?? "General"
            )
        }
        guard let json = try? JSONEncoder().encode(dtos),
              let jsonStr = String(data: json, encoding: .utf8) else { return [:] }

        let prompt = RecipePrompts.planVarietyCheckPrompt(draftPlanJSON: jsonStr)
        guard let raw = try? await inference.complete(prompt: prompt, maxNewTokens: 512),
              let extracted = raw.extractedJSON(),
              let data = extracted.data(using: .utf8) else { return [:] }

        struct SwapDTO: Decodable {
            let date: String
            let slot: String
        }
        guard let swaps = try? JSONDecoder().decode([SwapDTO].self, from: data),
              !swaps.isEmpty else { return [:] }

        // Re-run candidate selection for each flagged slot
        var result: [PlanDraftAssembler.SlotKey: Recipe] = [:]
        let usedIDs = Set(draft.values.map(\.id))

        for swap in swaps {
            guard let date = formatter.date(from: swap.date),
                  let slot = Slot.allCases.first(where: { $0.displayName == swap.slot }) else { continue }
            let key = PlanDraftAssembler.SlotKey(date: date, slot: slot)

            // Exclude the current recipe for this slot from candidates
            let currentID = draft[key]?.id
            var excludedForSwap = usedIDs
            if let c = currentID { excludedForSwap.remove(c) }

            let candidates = PlanCandidateFilter.candidates(
                from: pool,
                slot: slot,
                constraints: constraints,
                alreadyUsed: excludedForSwap
            )
            if let replacement = await pickViaLLM(candidates: candidates, date: date, slot: slot, constraints: constraints)
               ?? candidates.first {
                result[key] = replacement
            }
        }
        return result
    }

    private func describeConstraints(_ c: PlanConstraints) -> String {
        var parts: [String] = []
        if !c.dietaryTags.isEmpty { parts.append("Dietary: \(c.dietaryTags.joined(separator: ", "))") }
        if !c.excludedCuisines.isEmpty { parts.append("Exclude cuisines: \(c.excludedCuisines.joined(separator: ", "))") }
        if let maxSec = c.maxCookTimeSeconds { parts.append("Max cook time: \(maxSec / 60) min") }
        return parts.isEmpty ? "No special constraints" : parts.joined(separator: "; ")
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
