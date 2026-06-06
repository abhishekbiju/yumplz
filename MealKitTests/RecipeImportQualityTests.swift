import XCTest
@testable import MealKit

/// Programmatic regression loop for social-import quality issues:
/// wrong titles, hallucinated ingredients, hashtags in steps, card display.
final class RecipeImportQualityTests: XCTestCase {

    private let thakkaliSource = """
    Thakkali rasam — boil 4 tomatoes with tamarind, cumin, black pepper, garlic, \
    and curry leaves. Mash and strain. Temper mustard seeds in ghee. \
    Garnish with coriander.
    """

    private let thakkaliVideoTitle = "Thakkali Rasam Recipe | Easy South Indian Rasam #shorts"

    private func thakkaliContext() -> RecipeImportContext {
        RecipeImportContext(videoTitle: thakkaliVideoTitle, cleanedText: thakkaliSource)
    }

    private func badLLMOutput() -> ParsedRecipeDTO {
        ParsedRecipeDTO(
            title: "Pacha Puli Katharakai",
            summary: "Green tomato curry",
            servings: 2,
            ingredients: [
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "8 oz spaghetti",
                    quantity: 8,
                    unit: "oz",
                    name: "spaghetti",
                    storeCategory: "Pantry"
                ),
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "4 ripe tomatoes",
                    quantity: 4,
                    name: "tomatoes",
                    storeCategory: "Produce"
                ),
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "1 tsp tamarind paste",
                    quantity: 1,
                    unit: "tsp",
                    name: "tamarind",
                    storeCategory: "Pantry"
                ),
            ],
            steps: [
                ParsedRecipeDTO.ParsedStepDTO(text: "Boil tomatoes with spices."),
                ParsedRecipeDTO.ParsedStepDTO(
                    text: "Serve hot #rasam #southindian #foodie #tamilcooking #homemade"
                ),
            ],
            tags: ["#rasam", "south indian"],
            cuisine: "South Indian",
            dietaryTags: []
        )
    }

    // MARK: - SocialRecipeTextCleaner

    func testCleanerStripsHashtagsFromInstruction() {
        let raw = "Serve hot #rasam #southindian #foodie"
        let cleaned = SocialRecipeTextCleaner.cleanInstruction(raw)
        XCTAssertEqual(cleaned, "Serve hot")
        XCTAssertFalse(cleaned.contains("#"))
    }

    func testCleanerStripsPromoLinesFromSource() {
        let raw = """
        Tomatoes, tamarind, cumin.
        Subscribe for more recipes!
        Boil tomatoes until soft.
        """
        let cleaned = SocialRecipeTextCleaner.cleanSourceText(raw)
        XCTAssertTrue(cleaned.contains("Tomatoes"))
        XCTAssertFalse(cleaned.lowercased().contains("subscribe"))
    }

    // MARK: - RecipeImportSanitizer

    func testSanitizerPrefersVideoTitleOverWrongLLMTitle() {
        let fixed = RecipeImportSanitizer.sanitize(badLLMOutput(), context: thakkaliContext())
        XCTAssertEqual(fixed.title, "Thakkali Rasam")
    }

    func testSanitizerDropsHallucinatedPasta() {
        let fixed = RecipeImportSanitizer.sanitize(badLLMOutput(), context: thakkaliContext())
        XCTAssertFalse(fixed.ingredients.contains { $0.name.lowercased().contains("pasta") })
        XCTAssertFalse(fixed.ingredients.contains { $0.name.lowercased().contains("spaghetti") })
        XCTAssertTrue(fixed.ingredients.contains { $0.name.lowercased().contains("tomato") })
    }

    func testSanitizerStripsHashtagsFromLastStep() {
        let fixed = RecipeImportSanitizer.sanitize(badLLMOutput(), context: thakkaliContext())
        guard let last = fixed.steps.last else {
            return XCTFail("Expected steps")
        }
        XCTAssertFalse(last.text.contains("#"))
        XCTAssertTrue(last.text.lowercased().contains("serve"))
    }

    func testSanitizerStripsHashtagTags() {
        let fixed = RecipeImportSanitizer.sanitize(badLLMOutput(), context: thakkaliContext())
        XCTAssertFalse(fixed.tags.contains { $0.hasPrefix("#") })
    }

    // MARK: - RecipeImportEnricher

    func testEnricherBuildsMeasuredOriginalTextFromStructuredFields() {
        let dto = ParsedRecipeDTO(
            title: "Thakkali Rasam",
            ingredients: [
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "tomatoes",
                    quantity: 4,
                    name: "tomatoes",
                    storeCategory: "Produce"
                ),
            ],
            steps: [ParsedRecipeDTO.ParsedStepDTO(text: "Simmer.")],
            tags: [],
            dietaryTags: []
        )
        let enriched = RecipeImportEnricher.enrich(dto, context: thakkaliContext())
        XCTAssertEqual(enriched.ingredients.first?.originalText, "4 tomatoes")
    }

    func testEnricherParsesQuantityFromSourceText() {
        let parsed = RecipeImportEnricher.parseQuantityFromSource(
            name: "tomatoes",
            source: thakkaliSource
        )
        XCTAssertEqual(parsed?.quantity, 4)
    }

    func testEnricherInfersSouthIndianCuisineAndVegetarianTags() {
        let dto = ParsedRecipeDTO(
            title: "Thakkali Rasam",
            ingredients: [
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "4 tomatoes",
                    quantity: 4,
                    name: "tomatoes",
                    storeCategory: "Produce"
                ),
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "1 tsp cumin",
                    quantity: 1,
                    unit: "tsp",
                    name: "cumin",
                    storeCategory: "Spices & Baking"
                ),
            ],
            steps: [ParsedRecipeDTO.ParsedStepDTO(text: "Simmer tomatoes.")],
            tags: ["rasam"],
            dietaryTags: []
        )
        let enriched = RecipeImportEnricher.enrich(dto, context: thakkaliContext())
        XCTAssertEqual(enriched.cuisine, "South Indian")
        XCTAssertTrue(enriched.dietaryTags.contains("Vegetarian"))
        XCTAssertNotNil(enriched.cookTimeMinutes)
        XCTAssertNotNil(enriched.prepTimeMinutes)
    }

    func testIngredientDisplayFormatterUsesStructuredParseInDetailView() {
        let recipe = Recipe(title: "Test")
        recipe.servings = 4
        let ing = Ingredient(originalText: "tomatoes", orderIndex: 0)
        ing.parsedQuantity = 4
        ing.parsedName = "tomatoes"
        ing.recipe = recipe

        let text = IngredientDisplayFormatter.displayText(for: ing, recipe: recipe)
        XCTAssertEqual(text, "4 tomatoes")
    }

    // MARK: - RecipeDisplayFormatter

    func testDisplayFormatterExtractsRecipeNameFromVideoTitle() {
        let title = RecipeDisplayFormatter.recipeTitle(fromVideoTitle: thakkaliVideoTitle)
        XCTAssertEqual(title, "Thakkali Rasam")
    }

    func testCardTitleTruncatesLongNoisyTitles() {
        let long = String(repeating: "Tomato Rasam ", count: 8) + "#food #recipe"
        let card = RecipeDisplayFormatter.cardTitle(long)
        XCTAssertLessThanOrEqual(card.count, 53)
        XCTAssertFalse(card.contains("#"))
    }

    // MARK: - YouTube title extraction

    func testExtractYouTubeVideoTitleFromPlayerJSON() {
        let html = """
        <script>var ytInitialPlayerResponse = {"videoDetails":{"title":"Thakkali Rasam Recipe | Easy Rasam","shortDescription":"..."}};</script>
        """
        XCTAssertEqual(
            SocialURLRouter.extractYouTubeVideoTitle(from: html),
            "Thakkali Rasam Recipe | Easy Rasam"
        )
    }

    // MARK: - End-to-end sanitizer pipeline (mock LLM JSON)

    func testFullQualityPipelineFromMockBadJSON() throws {
        let context = thakkaliContext()
        let json = """
        {"title":"Pacha Puli Katharakai","servings":2,"ingredients":[
          {"originalText":"8 oz pasta","name":"pasta","storeCategory":"Pantry"},
          {"originalText":"4 tomatoes","name":"tomatoes","storeCategory":"Produce"}
        ],"steps":[
          {"text":"Simmer tomatoes.","isSectionHeader":false},
          {"text":"Enjoy #rasam #food","isSectionHeader":false}
        ],"tags":["#viral"],"dietaryTags":[]}
        """
        let dto = try RecipeJSONParser.parseRecipeDTO(from: json)
        let fixed = RecipeImportSanitizer.sanitize(dto, context: context)

        XCTAssertEqual(fixed.title, "Thakkali Rasam")
        XCTAssertEqual(fixed.ingredients.count, 1)
        XCTAssertEqual(fixed.ingredients[0].name, "tomatoes")
        XCTAssertFalse(fixed.steps.last!.text.contains("#"))
    }
}
