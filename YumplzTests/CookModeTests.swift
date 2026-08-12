import XCTest
import SwiftData
@testable import Yumplz

// MARK: - CookMode Tests

final class CookModeTests: XCTestCase {

    // MARK: Slice 1 — cookableSteps filters section headers

    @MainActor
    func testCookableStepsFiltersSectionHeaders() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Filter Test")
        let step1 = Step(text: "Mix", orderIndex: 0, isSectionHeader: false)
        let header = Step(text: "For the Sauce", orderIndex: 1, isSectionHeader: true)
        let step2 = Step(text: "Bake", orderIndex: 2, isSectionHeader: false)
        step1.recipe = recipe
        header.recipe = recipe
        step2.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = CookModeViewModel(recipe: recipe)

        XCTAssertEqual(vm.cookableSteps.count, 2)
        XCTAssertFalse(vm.cookableSteps.contains(where: { $0.isSectionHeader }))
    }

    // MARK: Slice 2 — goNext advances index, stops at last

    @MainActor
    func testGoNextAdvancesAndClampsAtLast() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Nav Test")
        let s1 = Step(text: "Step 1", orderIndex: 0)
        let s2 = Step(text: "Step 2", orderIndex: 1)
        s1.recipe = recipe
        s2.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = CookModeViewModel(recipe: recipe)
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertFalse(vm.isLastStep)

        vm.goNext()
        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertTrue(vm.isLastStep)

        vm.goNext()
        XCTAssertEqual(vm.currentStepIndex, 1, "Should not advance past the last step")
    }

    // MARK: Slice 3 — goPrev decreases, stops at first

    @MainActor
    func testGoPrevDecreasesAndClampsAtFirst() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Nav Test")
        let s1 = Step(text: "Step 1", orderIndex: 0)
        let s2 = Step(text: "Step 2", orderIndex: 1)
        s1.recipe = recipe
        s2.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = CookModeViewModel(recipe: recipe)
        XCTAssertTrue(vm.isFirstStep)

        vm.goPrev()
        XCTAssertEqual(vm.currentStepIndex, 0, "Should not go before the first step")

        vm.goNext()
        XCTAssertFalse(vm.isFirstStep)

        vm.goPrev()
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertTrue(vm.isFirstStep)
    }

    // MARK: Slice 4 — progressFraction is correct

    @MainActor
    func testProgressFraction() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Progress Test")
        let s1 = Step(text: "Step 1", orderIndex: 0)
        let s2 = Step(text: "Step 2", orderIndex: 1)
        let s3 = Step(text: "Step 3", orderIndex: 2)
        s1.recipe = recipe
        s2.recipe = recipe
        s3.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = CookModeViewModel(recipe: recipe)
        XCTAssertEqual(vm.progressFraction, 1.0 / 3.0, accuracy: 0.001)

        vm.goNext()
        XCTAssertEqual(vm.progressFraction, 2.0 / 3.0, accuracy: 0.001)

        vm.goNext()
        XCTAssertEqual(vm.progressFraction, 1.0, accuracy: 0.001)
    }

    // MARK: Slice 5 — finishCooking increments timesCooked

    @MainActor
    func testFinishCookingIncrementsTimesCooked() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Finish Test")
        recipe.timesCooked = 2
        let s1 = Step(text: "Step 1", orderIndex: 0)
        s1.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = CookModeViewModel(recipe: recipe)
        vm.finishCooking(context: context)

        let descriptor = FetchDescriptor<Recipe>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.timesCooked, 3)
        XCTAssertNotNil(fetched.first?.lastCookedAt)
    }

    // MARK: Slice 6 — CookModeTimer starts and reaches zero

    @MainActor
    func testTimerReachesZero() async throws {
        let timer = CookModeTimer(stepIndex: 0, totalSeconds: 1)
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(timer.remainingSeconds, 1)

        timer.start()
        XCTAssertEqual(timer.state, .running)

        try await Task.sleep(for: .seconds(2))

        XCTAssertEqual(timer.state, .finished)
        XCTAssertEqual(timer.remainingSeconds, 0)
    }

    // MARK: Slice 7 — CookModeTimer pause freezes countdown

    @MainActor
    func testTimerPauseFreezes() async throws {
        let timer = CookModeTimer(stepIndex: 0, totalSeconds: 3)

        timer.start()
        // Give the tick task at least one second to potentially decrement
        try await Task.sleep(for: .seconds(1))

        timer.pause()
        let frozenRemaining = timer.remainingSeconds
        XCTAssertEqual(timer.state, .paused)

        // Wait 2 more seconds — should not change since paused
        try await Task.sleep(for: .seconds(2))

        XCTAssertEqual(
            timer.remainingSeconds,
            frozenRemaining,
            "Remaining time should be frozen while paused"
        )
        XCTAssertEqual(timer.state, .paused)
    }

    // MARK: Slice 8 — MiseEnPlaceViewModel toggle moves item to checked

    @MainActor
    func testMiseEnPlaceToggle() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Mise Test")
        recipe.servings = 2
        let i1 = Ingredient(originalText: "1 cup flour", orderIndex: 0)
        let i2 = Ingredient(originalText: "2 eggs", orderIndex: 1)
        let i3 = Ingredient(originalText: "1 tsp salt", orderIndex: 2)
        i1.recipe = recipe
        i2.recipe = recipe
        i3.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = MiseEnPlaceViewModel(
            ingredients: [i1, i2, i3],
            servings: recipe.servings,
            recipeServings: recipe.servings
        )
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertEqual(vm.uncheckedItems.count, 3)
        XCTAssertEqual(vm.checkedItems.count, 0)

        let itemToToggle = vm.items[1]
        vm.toggle(item: itemToToggle)

        XCTAssertTrue(vm.items[1].isChecked)
        XCTAssertEqual(vm.uncheckedItems.count, 2)
        XCTAssertEqual(vm.checkedItems.count, 1)
        XCTAssertEqual(vm.checkedItems.first?.displayText, "2 eggs")
    }

    // MARK: Slice 9 — invalidateTimers stops background tick tasks

    @MainActor
    func testInvalidateTimersCancelsActiveTimers() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "Timer Cleanup")
        let step = Step(text: "Simmer", orderIndex: 0, timerSeconds: 60)
        step.recipe = recipe
        context.insert(recipe)
        try context.save()

        let vm = CookModeViewModel(recipe: recipe)
        vm.startTimer(for: step, at: 0)
        XCTAssertEqual(vm.timers.count, 1)

        vm.invalidateTimers()
        XCTAssertTrue(vm.timers.isEmpty)
    }
}
