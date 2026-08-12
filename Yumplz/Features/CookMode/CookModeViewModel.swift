import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CookModeViewModel {
    let recipe: Recipe
    private(set) var currentStepIndex: Int = 0
    private(set) var cookableSteps: [Step]
    var displayServings: Int
    private(set) var timers: [CookModeTimer] = []
    private(set) var miseEnPlace: MiseEnPlaceViewModel

    init(recipe: Recipe) {
        self.recipe = recipe
        self.cookableSteps = (recipe.steps ?? [])
            .filter { !$0.isSectionHeader }
            .sorted { $0.orderIndex < $1.orderIndex }
        self.displayServings = recipe.servings
        self.miseEnPlace = MiseEnPlaceViewModel(
            ingredients: recipe.ingredients ?? [],
            servings: recipe.servings,
            recipeServings: recipe.servings
        )
    }

    var isFirstStep: Bool {
        currentStepIndex == 0
    }

    var isLastStep: Bool {
        cookableSteps.isEmpty || currentStepIndex == cookableSteps.count - 1
    }

    var progressFraction: Double {
        guard !cookableSteps.isEmpty else { return 0 }
        return Double(currentStepIndex + 1) / Double(cookableSteps.count)
    }

    func goNext() {
        guard !isLastStep else { return }
        currentStepIndex += 1
    }

    func goPrev() {
        guard !isFirstStep else { return }
        currentStepIndex -= 1
    }

    func finishCooking(context: ModelContext) {
        recipe.timesCooked += 1
        recipe.lastCookedAt = Date()
        try? context.save()
    }

    func startTimer(for step: Step, at stepIndex: Int) {
        guard let seconds = step.timerSeconds else { return }
        let timer = CookModeTimer(stepIndex: stepIndex, totalSeconds: seconds)
        timers.append(timer)
        timer.start()
    }

    func removeTimer(_ timer: CookModeTimer) {
        timer.cancel()
        timers.removeAll { $0 === timer }
    }

    /// Stops every active countdown. Call when Cook Mode is dismissed so timer
    /// tasks cannot keep mutating this view model after the UI is gone.
    func invalidateTimers() {
        for timer in timers {
            timer.cancel()
        }
        timers.removeAll()
    }
}
