import XCTest
import SwiftData
@testable import MealKit

/// Regression loop for async background imports that surface as library cards.
final class AsyncImportTests: XCTestCase {

    @MainActor
    func testPlaceholderRecipeIsNotInteractive() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = ImportService.createPlaceholder(
            from: .url(URL(string: "https://www.example.com/recipe")!),
            in: context
        )

        XCTAssertFalse(recipe.isImportInteractive)
        XCTAssertTrue(recipe.isImportInProgress)
        XCTAssertEqual(recipe.importStatusLabel, ImportPhase.idle.displayLabel)
        XCTAssertEqual(recipe.title, "example.com")
    }

    @MainActor
    func testSyncImportPhaseUpdatesRecipeLabel() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let recipe = Recipe(title: "Pending")
        recipe.importPhaseRaw = ImportPhase.idle.storageKey
        context.insert(recipe)
        try context.save()

        recipe.importPhaseRaw = ImportPhase.parsingWithAI.storageKey
        try context.save()

        XCTAssertEqual(recipe.importStatusLabel, "Parsing with AI…")
        XCTAssertFalse(recipe.isImportInteractive)
    }

    @MainActor
    func testApplyClearsImportStateAndPopulatesRecipe() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let downloads = ModelDownloadManager()
        let service = ImportService(
            downloads: downloads,
            inference: InferenceService(),
            whisper: WhisperTranscriptionService()
        )

        let placeholder = ImportService.createPlaceholder(
            from: .url(URL(string: "https://chef.example.com/rasam")!),
            in: context
        )

        let dto = ParsedRecipeDTO(
            title: "Tomato Rasam",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            ingredients: [
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "4 tomatoes",
                    quantity: 4,
                    name: "tomatoes",
                    storeCategory: "Produce"
                ),
            ],
            steps: [ParsedRecipeDTO.ParsedStepDTO(text: "Simmer tomatoes.")],
            tags: ["rasam"],
            cuisine: "South Indian",
            dietaryTags: ["Vegetarian"]
        )

        try service.apply(dto, to: placeholder, in: context)

        XCTAssertTrue(placeholder.isImportInteractive)
        XCTAssertNil(placeholder.importPhaseRaw)
        XCTAssertEqual(placeholder.title, "Tomato Rasam")
        XCTAssertEqual(placeholder.ingredients?.count, 1)
        XCTAssertEqual(placeholder.steps?.count, 1)
    }

    @MainActor
    func testFailedImportMarksRecipeAsNonInteractiveWithMessage() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext
        let recipe = ImportService.createPlaceholder(
            from: .url(URL(string: "https://www.example.com/x")!),
            in: context
        )

        recipe.importPhaseRaw = ImportPhase.failed("Network error").storageKey
        recipe.importErrorMessage = "Network error"
        try context.save()

        XCTAssertFalse(recipe.isImportInteractive)
        XCTAssertTrue(recipe.importFailed)
        XCTAssertEqual(recipe.importStatusLabel, "Network error")
    }
}
