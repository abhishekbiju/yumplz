import XCTest
import SwiftData
@testable import MealKit

// MARK: - Helpers

@MainActor
private func makeRecipe(
    title: String,
    cuisine: String? = nil,
    dietaryTags: [String] = [],
    cookTimeSeconds: Int? = nil,
    in context: ModelContext
) -> Recipe {
    let r = Recipe(title: title)
    r.cuisine = cuisine
    r.dietaryTags = dietaryTags
    r.cookTimeSeconds = cookTimeSeconds
    context.insert(r)
    return r
}

// Fixed Monday for deterministic date tests
private var testMonday: Date {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 1; comps.day = 5  // Monday
    return Calendar.current.date(from: comps)!
}

// MARK: - Tests

@MainActor
final class PlanGenerationTests: XCTestCase {

    // ── Slice 1 ──────────────────────────────────────────────────────────
    // passesConstraints returns true with no constraints

    func testPassesConstraintsNoRestrictions() throws {
        let container = try TestModelContainer.make()
        let r = makeRecipe(title: "Pasta", in: container.mainContext)
        let constraints = PlanConstraints.default
        XCTAssertTrue(PlanCandidateFilter.passesConstraints(r, constraints: constraints))
    }

    // ── Slice 2 ──────────────────────────────────────────────────────────
    // Dietary tag filter — recipe must have ALL required tags

    func testDietaryFilterRequiresAllTags() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let vegan = makeRecipe(title: "Vegan Bowl", dietaryTags: ["vegan", "vegetarian"], in: ctx)
        let vegOnly = makeRecipe(title: "Veg Soup", dietaryTags: ["vegetarian"], in: ctx)
        let meat = makeRecipe(title: "Chicken", dietaryTags: [], in: ctx)

        var constraints = PlanConstraints.default
        constraints.dietaryTags = ["vegan"]

        XCTAssertTrue(PlanCandidateFilter.passesConstraints(vegan, constraints: constraints))
        XCTAssertFalse(PlanCandidateFilter.passesConstraints(vegOnly, constraints: constraints))
        XCTAssertFalse(PlanCandidateFilter.passesConstraints(meat, constraints: constraints))
    }

    // ── Slice 3 ──────────────────────────────────────────────────────────
    // Cuisine exclusion filter

    func testCuisineExclusionFilter() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let italian = makeRecipe(title: "Pasta", cuisine: "Italian", in: ctx)
        let mexican = makeRecipe(title: "Tacos", cuisine: "Mexican", in: ctx)

        var constraints = PlanConstraints.default
        constraints.excludedCuisines = ["Italian"]

        XCTAssertFalse(PlanCandidateFilter.passesConstraints(italian, constraints: constraints))
        XCTAssertTrue(PlanCandidateFilter.passesConstraints(mexican, constraints: constraints))
    }

    // ── Slice 4 ──────────────────────────────────────────────────────────
    // Max cook time filter

    func testMaxCookTimeFilter() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let quick = makeRecipe(title: "Salad", cookTimeSeconds: 10 * 60, in: ctx)    // 10 min
        let slow = makeRecipe(title: "Roast", cookTimeSeconds: 90 * 60, in: ctx)     // 90 min
        let noTime = makeRecipe(title: "Snack", cookTimeSeconds: nil, in: ctx)        // nil

        var constraints = PlanConstraints.default
        constraints.maxCookTimeSeconds = 30 * 60  // 30 min max

        XCTAssertTrue(PlanCandidateFilter.passesConstraints(quick, constraints: constraints))
        XCTAssertFalse(PlanCandidateFilter.passesConstraints(slow, constraints: constraints))
        // nil totalTimeSeconds means unknown — should pass (not penalise)
        XCTAssertTrue(PlanCandidateFilter.passesConstraints(noTime, constraints: constraints))
    }

    // ── Slice 5 ──────────────────────────────────────────────────────────
    // candidates() excludes already-used recipe IDs

    func testCandidatesExcludesAlreadyUsed() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let r1 = makeRecipe(title: "R1", in: ctx)
        let r2 = makeRecipe(title: "R2", in: ctx)
        let r3 = makeRecipe(title: "R3", in: ctx)
        try ctx.save()

        let used: Set<UUID> = [r1.id, r2.id]
        let pool = [r1, r2, r3]
        let constraints = PlanConstraints.default

        let result = PlanCandidateFilter.candidates(
            from: pool, slot: .dinner,
            constraints: constraints,
            alreadyUsed: used
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "R3")
    }

    // ── Slice 6 ──────────────────────────────────────────────────────────
    // candidates() respects the limit parameter

    func testCandidatesRespectLimit() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let recipes = (1...15).map { makeRecipe(title: "R\($0)", in: ctx) }
        try ctx.save()

        let result = PlanCandidateFilter.candidates(
            from: recipes, slot: .lunch,
            constraints: .default,
            alreadyUsed: [],
            limit: 5
        )
        XCTAssertEqual(result.count, 5)
    }

    // ── Slice 7 ──────────────────────────────────────────────────────────
    // enumerateSlots produces correct count: days × 4 slots

    func testEnumerateSlotsCount() {
        let inference = InferenceService()
        let downloads = ModelDownloadManager()
        let service = PlanGenerationService(inference: inference, downloads: downloads)

        let slots = service.enumerateSlots(startDate: testMonday, days: 3)
        XCTAssertEqual(slots.count, 12)   // 3 days × 4 slots
    }

    // ── Slice 8 ──────────────────────────────────────────────────────────
    // enumerateSlots first date is start-of-day(startDate)

    func testEnumerateSlotsFirstDateIsStartOfDay() {
        let inference = InferenceService()
        let downloads = ModelDownloadManager()
        let service = PlanGenerationService(inference: inference, downloads: downloads)

        let slots = service.enumerateSlots(startDate: testMonday, days: 1)
        let expectedStart = Calendar.current.startOfDay(for: testMonday)
        XCTAssertEqual(slots.first?.0, expectedStart)
    }

    // ── Slice 9 ──────────────────────────────────────────────────────────
    // PlanDraftAssembler.assemble orders meals by date then slot order

    func testDraftAssemblerOrdering() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let r1 = makeRecipe(title: "Breakfast dish", in: ctx)
        let r2 = makeRecipe(title: "Dinner dish", in: ctx)
        try ctx.save()

        let day = testMonday
        var selections: [PlanDraftAssembler.SlotKey: Recipe] = [:]
        selections[.init(date: day, slot: .dinner)] = r2
        selections[.init(date: day, slot: .breakfast)] = r1

        let draft = PlanDraftAssembler.assemble(selections: selections, servings: 2)
        XCTAssertEqual(draft.count, 2)
        XCTAssertEqual(draft[0].slot, .breakfast)  // breakfast sorts before dinner
        XCTAssertEqual(draft[1].slot, .dinner)
    }

    // ── Slice 10 ─────────────────────────────────────────────────────────
    // PlanDraftAssembler.commit writes PlannedMeals to SwiftData

    func testDraftAssemblerCommitPersists() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let recipe = makeRecipe(title: "Scrambled Eggs", in: ctx)
        try ctx.save()

        let draft = [DraftMeal(date: testMonday, slot: .breakfast, recipe: recipe, plannedServings: 2)]
        _ = PlanDraftAssembler.commit(
            draft: draft,
            recipeFor: { $0 == recipe.id ? recipe : nil },
            context: ctx
        )

        let meals = try ctx.fetch(FetchDescriptor<PlannedMeal>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.slot, .breakfast)
        XCTAssertEqual(meals.first?.plannedServings, 2)
        XCTAssertEqual(meals.first?.recipe?.title, "Scrambled Eggs")
    }

    // ── Slice 11 ─────────────────────────────────────────────────────────
    // commit skips DraftMeals whose recipe ID is not in the pool

    func testDraftAssemblerSkipsMissingRecipes() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let recipe = makeRecipe(title: "Real Recipe", in: ctx)
        try ctx.save()

        let ghostRecipe = Recipe(title: "Ghost")  // not inserted

        let draft = [
            DraftMeal(date: testMonday, slot: .lunch, recipe: ghostRecipe, plannedServings: 1),
            DraftMeal(date: testMonday, slot: .dinner, recipe: recipe, plannedServings: 2),
        ]
        _ = PlanDraftAssembler.commit(
            draft: draft,
            recipeFor: { $0 == recipe.id ? recipe : nil },
            context: ctx
        )

        let meals = try ctx.fetch(FetchDescriptor<PlannedMeal>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.slot, .dinner)
    }
}
