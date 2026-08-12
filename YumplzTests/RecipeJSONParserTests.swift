import XCTest
@testable import Yumplz

final class RecipeJSONParserTests: XCTestCase {

    func testExtractedJSONObject_balancedBracesWithPreamble() {
        let raw = """
        Here is the recipe JSON:
        {"title":"Pasta","servings":2,"ingredients":[],"steps":[],"tags":[],"dietaryTags":[]}
        Done.
        """
        let json = raw.extractedJSONObject()
        XCTAssertEqual(json, "{\"title\":\"Pasta\",\"servings\":2,\"ingredients\":[],\"steps\":[],\"tags\":[],\"dietaryTags\":[]}")
    }

    func testExtractedJSONObject_ignoresTrailingGarbageAfterObject() {
        let raw = """
        {"title":"Soup","servings":4,"ingredients":[],"steps":[],"tags":[],"dietaryTags":[]}
        extra text with } brace
        """
        let json = raw.extractedJSONObject()
        XCTAssertTrue(json?.hasSuffix("}") == true)
        XCTAssertFalse(json?.contains("extra text") == true)
    }

    func testParseRecipeDTO_missingOptionalKeysUsesDefaults() throws {
        let raw = """
        Sure! {"title":"Tomato Soup","servings":3,"ingredients":[{"originalText":"2 tomatoes","name":"tomatoes"}],"steps":[{"text":"Simmer."}]}
        """
        let dto = try RecipeJSONParser.parseRecipeDTO(from: raw)
        XCTAssertEqual(dto.title, "Tomato Soup")
        XCTAssertEqual(dto.servings, 3)
        XCTAssertEqual(dto.tags, [])
        XCTAssertEqual(dto.dietaryTags, [])
        XCTAssertEqual(dto.ingredients.first?.storeCategory, "Other")
        XCTAssertEqual(dto.steps.first?.isSectionHeader, false)
    }

    func testParseRecipeDTO_minimalIngredientUsesOriginalTextAsName() throws {
        let raw = #"{"title":"Salad","servings":1,"ingredients":[{"originalText":"1 cucumber"}],"steps":[{"text":"Chop."}],"tags":[],"dietaryTags":[]}"#
        let dto = try RecipeJSONParser.parseRecipeDTO(from: raw)
        XCTAssertEqual(dto.ingredients.first?.name, "1 cucumber")
    }

    func testParseRecipeDTO_missingTitleUsesFallback() throws {
        let raw = #"{"servings":2,"ingredients":[{"originalText":"salt","name":"salt"}],"steps":[{"text":"Mix."}],"tags":[],"dietaryTags":[]}"#
        let dto = try RecipeJSONParser.parseRecipeDTO(from: raw)
        XCTAssertEqual(dto.title, "Imported Recipe")
    }

    func testParseRecipeDTO_noJSONThrows() {
        XCTAssertThrowsError(try RecipeJSONParser.parseRecipeDTO(from: "no json here")) { error in
            guard case InferenceError.noJSONInResponse = error else {
                return XCTFail("Expected noJSONInResponse, got \(error)")
            }
        }
    }

    func testExtractedJSONObject_repairsTruncatedMidObject() {
        let truncated = """
        {"title":"Creamy Chicken Cajun Pasta","servings":4,"ingredients":[{"originalText":"2 chicken breasts","name":"chicken breasts"},{"originalText":"1 lb penne
        """
        let json = truncated.extractedJSONObject()
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.hasSuffix("}") == true)
    }

    func testParseRecipeDTO_repairsTruncatedLLMOutput() throws {
        let truncated = """
        {"title":"Creamy Chicken Cajun Pasta","servings":4,"prepTimeMinutes":10,"cookTimeMinutes":20,"ingredients":[{"originalText":"2 chicken breasts","quantity":2,"name":"chicken breasts","storeCategory":"Meat & Seafood"},{"originalText":"1 lb penne","quantity":1,"unit":"lb","name":"penne","storeCategory":"Pantry"}],"steps":[{"text":"Cook pasta.","isSectionHeader":false},{"text":"Sauté chicken with cajun spice.","isSectionHeader":false}],"tags":["cajun","pasta"],"cuisine":"American","dietaryTags":["Gluten-Free"]
        """
        let dto = try RecipeJSONParser.parseRecipeDTO(from: truncated)
        XCTAssertEqual(dto.title, "Creamy Chicken Cajun Pasta")
        XCTAssertEqual(dto.ingredients.count, 2)
        XCTAssertEqual(dto.steps.count, 2)
    }

    func testParseRecipeDTO_repairsTruncatedTitleOnlySeed() throws {
        let truncated = #"{"title":"Cajun Pasta","servings":4,"ingredients":[{"originalText":"1 tsp cajun seasoning","name":"cajun seasoning","storeCategory":"Spices & Baking"}],"steps":[{"text":"Season and cook.","isSectionHeader":false}],"tags":[],"dietaryTags":[]"#
        let dto = try RecipeJSONParser.parseRecipeDTO(from: truncated)
        XCTAssertEqual(dto.title, "Cajun Pasta")
        XCTAssertFalse(dto.ingredients.isEmpty)
        XCTAssertFalse(dto.steps.isEmpty)
    }
}

final class RecipePromptTests: XCTestCase {

    func testLlamaChatFormatting_usesRealSpecialTokens() {
        let formatted = LlamaChatFormatting.prompt(system: "sys", user: "usr")
        XCTAssertTrue(formatted.contains("<|" + "start_header_id" + "|>"))
        XCTAssertTrue(formatted.contains("<|" + "end_header_id" + "|>"))
        XCTAssertTrue(formatted.contains("<|" + "eot_id" + "|>"))
        XCTAssertFalse(formatted.contains("redacted_start_header_id"))
    }

    func testRecipeExtractionPrompt_includesConcreteExample() {
        let prompt = RecipePrompts.recipeExtractionPrompt(from: "Simmer tomatoes with tamarind.")
        XCTAssertTrue(prompt.contains("\"title\":\"Thakkali Rasam\""))
        XCTAssertTrue(prompt.contains("Output ONLY the JSON object"))
        XCTAssertTrue(prompt.contains("Simmer tomatoes with tamarind."))
        XCTAssertTrue(prompt.contains("Do not invent ingredients"))
        XCTAssertTrue(prompt.contains("estimate realistic quantities"))
    }

    func testCompactRecipeExtractionPrompt_isMinimalJSON() {
        let prompt = RecipePrompts.compactRecipeExtractionPrompt(from: "Quick tacos.")
        XCTAssertTrue(prompt.contains("Return ONE JSON object only"))
        XCTAssertTrue(prompt.contains("Quick tacos."))
    }
}

/// Runs the real on-device model when available. Enable with YUMPLZ_LIVE_LLM=1.
final class RecipePromptLiveTests: XCTestCase {

    private let sampleYouTubeDescription = """
    Garlic butter pasta recipe 🍝 Boil 8 oz spaghetti. Melt 3 tbsp butter, sauté 4 minced \
    garlic cloves 1 minute. Toss pasta with garlic butter and 1/4 cup parmesan. Serves 2. \
    Ready in 20 minutes.
    """

    override func setUp() async throws {
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["YUMPLZ_LIVE_LLM"] == "1" else {
            throw XCTSkip("Set YUMPLZ_LIVE_LLM=1 to run live Llama prompt tests")
        }
    }

    @MainActor
    func testLiveParseRecipe_fromYouTubeStyleDescription() async throws {
        let modelURL = ModelDownloadManager.modelsDirectory
            .appending(path: LocalModel.llama3_2_3b.rawValue)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw XCTSkip("Download the Llama model in-app first: \(modelURL.path)")
        }

        let inference = InferenceService()
        try await inference.load(modelURL: modelURL)
        defer { Task { await inference.unload() } }

        let dto = try await inference.parseRecipe(from: sampleYouTubeDescription)

        XCTAssertFalse(dto.title.isEmpty)
        XCTAssertGreaterThanOrEqual(dto.servings, 1)
        XCTAssertFalse(dto.ingredients.isEmpty, "Expected at least one ingredient")
        XCTAssertFalse(dto.steps.isEmpty, "Expected at least one step")
        XCTAssertTrue(
            dto.ingredients.contains { $0.originalText.lowercased().contains("garlic")
                || $0.name.lowercased().contains("garlic")
                || $0.originalText.lowercased().contains("pasta")
                || $0.name.lowercased().contains("pasta") },
            "Expected pasta or garlic in ingredients, got: \(dto.ingredients.map(\.originalText))"
        )
    }
}
