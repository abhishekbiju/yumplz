import XCTest
import SwiftData
@testable import MealKit

final class PlanTests: XCTestCase {

    // MARK: - Slice 1 — daysInCurrentWeek returns 7 dates starting from currentWeekStart

    @MainActor
    func testDaysInCurrentWeekReturnsSeven() {
        let vm = PlanViewModel()
        let days = vm.daysInCurrentWeek
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, vm.currentWeekStart)
    }

    // MARK: - Slice 2 — nextWeek advances currentWeekStart by 7 days

    @MainActor
    func testNextWeekAdvancesBySevenDays() {
        let vm = PlanViewModel()
        let before = vm.currentWeekStart
        vm.nextWeek()
        let expected = Calendar.current.date(byAdding: .day, value: 7, to: before)!
        XCTAssertEqual(vm.currentWeekStart, expected)
    }

    // MARK: - Slice 3 — prevWeek decrements currentWeekStart by 7 days

    @MainActor
    func testPrevWeekDecrementsBySevenDays() {
        let vm = PlanViewModel()
        let before = vm.currentWeekStart
        vm.prevWeek()
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: before)!
        XCTAssertEqual(vm.currentWeekStart, expected)
    }

    // MARK: - Slice 4 — recipe-backed PlannedMeal persists to SwiftData

    @MainActor
    func testRecipeBackedMealPersists() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let recipe = Recipe(title: "Grilled Salmon")
        ctx.insert(recipe)

        let meal = PlannedMeal(date: Date(), slot: .dinner, recipe: recipe)
        meal.plannedServings = 2
        ctx.insert(meal)
        try ctx.save()

        let meals = try ctx.fetch(FetchDescriptor<PlannedMeal>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.recipe?.title, "Grilled Salmon")
        XCTAssertFalse(meals.first?.isNoteOnly ?? true)
    }

    // MARK: - Slice 5 — note-only PlannedMeal persists with isNoteOnly==true

    @MainActor
    func testNoteOnlyMealPersists() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let meal = PlannedMeal(date: Date(), slot: .lunch, noteText: "Leftovers")
        ctx.insert(meal)
        try ctx.save()

        let meals = try ctx.fetch(FetchDescriptor<PlannedMeal>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertNil(meals.first?.recipe)
        XCTAssertEqual(meals.first?.noteText, "Leftovers")
        XCTAssertTrue(meals.first?.isNoteOnly ?? false)
    }

    // MARK: - Slice 6 — marking as cooked sets isCooked=true and updates recipe.timesCooked

    @MainActor
    func testMarkAsCooked() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext

        let recipe = Recipe(title: "Pasta")
        recipe.timesCooked = 0
        ctx.insert(recipe)

        let meal = PlannedMeal(date: Date(), slot: .dinner, recipe: recipe)
        ctx.insert(meal)
        try ctx.save()

        meal.isCooked = true
        meal.cookedAt = Date()
        meal.recipe?.timesCooked += 1
        meal.recipe?.lastCookedAt = Date()
        try ctx.save()

        let fetchedMeals = try ctx.fetch(FetchDescriptor<PlannedMeal>())
        let fetchedRecipes = try ctx.fetch(FetchDescriptor<Recipe>())

        XCTAssertTrue(fetchedMeals.first?.isCooked ?? false)
        XCTAssertNotNil(fetchedMeals.first?.cookedAt)
        XCTAssertEqual(fetchedRecipes.first?.timesCooked, 1)
        XCTAssertNotNil(fetchedRecipes.first?.lastCookedAt)
    }
}
