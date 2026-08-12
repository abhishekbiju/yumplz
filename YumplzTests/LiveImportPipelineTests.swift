import XCTest
@testable import Yumplz

/// Verifies the social-import pipeline against a real public demo video:
/// https://www.youtube.com/shorts/6UuseD5McGE (Pacha Puli Katharikai).
///
/// Offline tests use recorded page text. Set `YUMPLZ_LIVE_PIPELINE=1` to hit the network.
final class LiveImportPipelineTests: XCTestCase {

    private let demoURL = URL(string: "https://www.youtube.com/shorts/6UuseD5McGE")!
    private let demoVideoTitle = "Pacha Puli Katharikai Recipe | Easy South Indian #shorts"

    /// Recorded from live YouTube `shortDescription` on 2026-06-13.
    private static let recordedDescription = """
    My favorite go to easy recipes in recent times!!
    This recipe will make you fall in love with it instantly after the first bite

    Pacha Puli katharikai or Katharikai puli sambal

    Recipe

    Fry the eggplant in sesame or coconut oil
    Fry some dried chillies in the same oil

    For grinding you can use a mixer grind or a mortar and pestle

    Add the fried chilies with salt
    Grind it finely
    Onion - handful (roughly chopped)
    Curry leaves
    Coriander leaves
    Pound it
    Add the fried eggplant
    Crush it
    Add tamarind extract - 1/2 cup (thick)
    Oil - 1 tbsp (that we used for frying)
    Mix it well until it gets combined
    Enjoy

    Follow for easy recipes

    #lunch #southindianfood #eggplantrecipes #katharikai #brinjal
    """

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = .mockEphemeral
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    // MARK: - Recorded demo (always runs, no network)

    @MainActor
    func testRecordedDemoDescription_passesMinimumContentThreshold() {
        let context = RecipeImportContext(
            videoTitle: demoVideoTitle,
            cleanedText: Self.recordedDescription
        )
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40)
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("katharikai"))
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("eggplant"))
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("tamarind"))
        XCTAssertFalse(context.cleanedText.lowercased().contains("subscribe"))
    }

    @MainActor
    func testRecordedDemoDescription_mockedYouTubeShortPage_routesToRecipeText() async throws {
        let escaped = Self.recordedDescription
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("/shorts/") == true }) { req in
            let html = """
            <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"shortDescription":"\(escaped)"}};</script></body></html>
            """
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(html.utf8))
        }
        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let result = try await SocialURLRouter.route(url: demoURL, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("katharikai"))
    }

    @MainActor
    func testRecordedDemoDescription_shareExtensionPipeline_deliversImportRoute() async throws {
        let sharedURL = demoURL.absoluteString
        PendingImportStore.drain()
        PendingImportStore.append(PendingImportItem(kind: .url, value: sharedURL, autoStartImport: true))

        let deliveries = ShareImportDelivery.drainAndDeliver()
        XCTAssertEqual(deliveries.count, 1)

        let note = ShareImportDelivery.makeDeepLinkNotification(for: PendingImportItem(
            kind: deliveries[0].importKind,
            value: sharedURL,
            autoStartImport: deliveries[0].autoStartImport
        ))
        let route = ImportDeepLinkRouter.route(payload: note.object, userInfo: note.userInfo)
        XCTAssertEqual(route.importURL, sharedURL)
        XCTAssertTrue(route.autoStartImport)

        let escaped = Self.recordedDescription
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("/shorts/") == true }) { req in
            let html = """
            <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"shortDescription":"\(escaped)"}};</script></body></html>
            """
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(html.utf8))
        }
        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        guard let importURL = URL(string: sharedURL) else {
            return XCTFail("Invalid demo URL")
        }
        let socialResult = try await SocialURLRouter.route(url: importURL, session: session)
        guard case .recipeText(let context) = socialResult else {
            return XCTFail("Expected recipe text, got \(socialResult)")
        }
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40)
    }

    @MainActor
    func testRecordedDemoDescription_sanitizerDropsHallucinatedIngredients() {
        let context = RecipeImportContext(
            videoTitle: demoVideoTitle,
            cleanedText: Self.recordedDescription
        )

        let hallucinated = ParsedRecipeDTO(
            title: "Pacha Puli Katharikai",
            summary: "South Indian eggplant sambal",
            servings: 4,
            ingredients: [
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "8 oz spaghetti",
                    quantity: 8,
                    unit: "oz",
                    name: "spaghetti",
                    storeCategory: "Pantry"
                ),
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "1 eggplant",
                    quantity: 1,
                    name: "eggplant",
                    storeCategory: "Produce"
                ),
                ParsedRecipeDTO.ParsedIngredientDTO(
                    originalText: "1/2 cup tamarind extract",
                    quantity: 0.5,
                    unit: "cup",
                    name: "tamarind extract",
                    storeCategory: "Pantry"
                ),
            ],
            steps: [
                ParsedRecipeDTO.ParsedStepDTO(text: "Fry eggplant until golden."),
                ParsedRecipeDTO.ParsedStepDTO(
                    text: "Mix with tamarind and serve hot #foodie #recipe"
                ),
            ],
            tags: ["#katharikai"],
            cuisine: "South Indian",
            dietaryTags: ["Vegetarian"]
        )

        let sanitized = RecipeImportSanitizer.sanitize(hallucinated, context: context)
        XCTAssertTrue(sanitized.title.localizedCaseInsensitiveContains("katharikai"))
        XCTAssertFalse(sanitized.ingredients.contains { $0.name.localizedCaseInsensitiveContains("spaghetti") })
        XCTAssertTrue(sanitized.ingredients.contains { $0.name.localizedCaseInsensitiveContains("eggplant") })
        XCTAssertFalse(sanitized.steps.contains { $0.text.contains("#") })
    }

    // MARK: - Live network (optional)

    @MainActor
    func testLiveDemoYouTubeShort_extractsRecipeTextFromNetwork() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YUMPLZ_LIVE_PIPELINE"] == "1",
            "Set YUMPLZ_LIVE_PIPELINE=1 for live network verification"
        )

        let result = try await SocialURLRouter.route(url: demoURL, session: .shared)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText from live YouTube, got \(result)")
        }
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40)
        XCTAssertTrue(
            context.cleanedText.localizedCaseInsensitiveContains("katharikai")
                || context.cleanedText.localizedCaseInsensitiveContains("eggplant")
        )
    }

    /// Long-form (non-Shorts) YouTube video with a single recipe:
    /// https://www.youtube.com/watch?v=NCxBc3dF8wc (Chicken Lazone | Food Wishes).
    @MainActor
    func testLiveYouTubeLongForm_extractsRecipeTextFromNetwork() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YUMPLZ_LIVE_PIPELINE"] == "1",
            "Set YUMPLZ_LIVE_PIPELINE=1 for live network verification"
        )

        let url = URL(string: "https://www.youtube.com/watch?v=NCxBc3dF8wc")!
        let result = try await SocialURLRouter.route(url: url, session: .shared)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText from live YouTube long-form video, got \(result)")
        }
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40)
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("lazone"))
    }

    /// Real TikTok post with a full recipe in the caption (Tier 1 path):
    /// https://www.tiktok.com/@recipeincaption/video/7653217606027037970 (Lemon Garlic Alfredo Spaghetti).
    @MainActor
    func testLiveTikTokCaptionRecipe_extractsRecipeTextFromNetwork() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YUMPLZ_LIVE_PIPELINE"] == "1",
            "Set YUMPLZ_LIVE_PIPELINE=1 for live network verification"
        )

        let url = URL(string: "https://www.tiktok.com/@recipeincaption/video/7653217606027037970")!
        let result = try await SocialURLRouter.route(url: url, session: .shared)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText from live TikTok caption, got \(result)")
        }
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40)
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("spaghetti"))
    }
}
