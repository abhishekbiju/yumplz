import XCTest
import SwiftData
@testable import MealKit

final class LibrarySearchTests: XCTestCase {

    // MARK: - Slice 1 — empty query returns all

    @MainActor
    func testEmptyQueryReturnsAll() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext
        let r1 = Recipe(title: "Pasta"); ctx.insert(r1)
        let r2 = Recipe(title: "Soup"); ctx.insert(r2)
        try ctx.save()

        let vm = LibrarySearchViewModel()
        XCTAssertEqual(vm.filter([r1, r2]).count, 2)
    }

    // MARK: - Slice 2 — query filters by title (case-insensitive)

    @MainActor
    func testQueryFiltersByTitle() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext
        let pasta = Recipe(title: "Pasta Carbonara"); ctx.insert(pasta)
        let soup = Recipe(title: "Tomato Soup"); ctx.insert(soup)
        try ctx.save()

        let vm = LibrarySearchViewModel()
        vm.query = "pasta"
        let result = vm.filter([pasta, soup])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Pasta Carbonara")
    }

    // MARK: - Slice 3 — query matches cuisine

    @MainActor
    func testQueryMatchesCuisine() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext
        let pizza = Recipe(title: "Pizza"); pizza.cuisine = "Italian"; ctx.insert(pizza)
        let tacos = Recipe(title: "Tacos"); tacos.cuisine = "Mexican"; ctx.insert(tacos)
        try ctx.save()

        let vm = LibrarySearchViewModel()
        vm.query = "Italian"
        let result = vm.filter([pizza, tacos])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Pizza")
    }

    // MARK: - Slice 4 — dietary tag filter requires ALL selected tags

    @MainActor
    func testDietaryTagFilterRequiresAll() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext
        let r1 = Recipe(title: "Vegan Salad")
        r1.dietaryTags = ["Vegan", "Gluten-Free"]
        ctx.insert(r1)
        let r2 = Recipe(title: "Veggie Burger")
        r2.dietaryTags = ["Vegetarian"]
        ctx.insert(r2)
        try ctx.save()

        let vm = LibrarySearchViewModel()
        vm.selectedDietaryTags = ["Vegan", "Gluten-Free"]
        let result = vm.filter([r1, r2])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Vegan Salad")
    }

    // MARK: - Slice 5 — maxCookTime filters by totalTimeSeconds

    @MainActor
    func testMaxCookTimeFilters() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext
        let quick = Recipe(title: "Quick Oats")
        quick.cookTimeSeconds = 5 * 60
        ctx.insert(quick)
        let slow = Recipe(title: "Braised Short Ribs")
        slow.cookTimeSeconds = 3 * 3600
        ctx.insert(slow)
        try ctx.save()

        let vm = LibrarySearchViewModel()
        vm.maxCookTimeSeconds = 30 * 60
        let result = vm.filter([quick, slow])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Quick Oats")
    }

    // MARK: - Slice 6 — combined filters are AND

    @MainActor
    func testCombinedFiltersAreAnd() throws {
        let container = try TestModelContainer.make()
        let ctx = container.mainContext
        let r1 = Recipe(title: "Fast Vegan Bowl")
        r1.cuisine = "Asian"; r1.dietaryTags = ["Vegan"]; r1.cookTimeSeconds = 15 * 60
        ctx.insert(r1)
        let r2 = Recipe(title: "Slow Vegan Stew")
        r2.cuisine = "French"; r2.dietaryTags = ["Vegan"]; r2.cookTimeSeconds = 2 * 3600
        ctx.insert(r2)
        let r3 = Recipe(title: "Fast Asian Chicken")
        r3.cuisine = "Asian"; r3.cookTimeSeconds = 15 * 60
        ctx.insert(r3)
        try ctx.save()

        let vm = LibrarySearchViewModel()
        vm.query = "asian"
        vm.selectedDietaryTags = ["Vegan"]
        vm.maxCookTimeSeconds = 30 * 60
        let result = vm.filter([r1, r2, r3])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Fast Vegan Bowl")
    }

    // MARK: - Slice 7 — hasActiveFilters false at default, true when any filter set

    @MainActor
    func testHasActiveFilters() {
        let vm = LibrarySearchViewModel()
        XCTAssertFalse(vm.hasActiveFilters)

        vm.query = "pasta"
        XCTAssertTrue(vm.hasActiveFilters)
        vm.query = ""
        XCTAssertFalse(vm.hasActiveFilters)

        vm.selectedDietaryTags = ["Vegan"]
        XCTAssertTrue(vm.hasActiveFilters)
        vm.selectedDietaryTags = []
        XCTAssertFalse(vm.hasActiveFilters)

        vm.maxCookTimeSeconds = 1800
        XCTAssertTrue(vm.hasActiveFilters)
        vm.maxCookTimeSeconds = nil
        XCTAssertFalse(vm.hasActiveFilters)
    }

    // MARK: - Slice 8 — clearAll resets everything

    @MainActor
    func testClearAllResetsToDefault() {
        let vm = LibrarySearchViewModel()
        vm.query = "pasta"
        vm.selectedDietaryTags = ["Vegan"]
        vm.maxCookTimeSeconds = 1800
        vm.clearAll()

        XCTAssertEqual(vm.query, "")
        XCTAssertTrue(vm.selectedDietaryTags.isEmpty)
        XCTAssertNil(vm.maxCookTimeSeconds)
        XCTAssertFalse(vm.hasActiveFilters)
    }
}
