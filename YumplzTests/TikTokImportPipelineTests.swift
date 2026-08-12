import XCTest
@testable import Yumplz

/// End-to-end TikTok import regression loop: route → RecipeImportContext → validation.
final class TikTokImportPipelineTests: XCTestCase {

    private let userURL = URL(string:
        "https://www.tiktok.com/@recipes/video/7312508978880154888?is_from_webapp=1&sender_device=pc"
    )!

    private let cajunCaption = """
    You guys need to try this creamy chicken cajun pasta. This pasta recipe is your ticket \
    to a quick dinner solution. It is a one pan meal, ideal for those busy weeknights. \
    What pasta should we make next?
    """

    private let oEmbedJSON = """
    {
      "title": "You guys need to try this creamy chicken cajun pasta. One pan meal.",
      "author_name": "Viral Recipes"
    }
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

    // MARK: - Reproduces the user-visible failure mode

    @MainActor
    func testTikTokShellHTMLScrape_isTooShortForValidation() {
        let shellHTML = """
        <!DOCTYPE html><html><head><title>TikTok - Make Your Day</title></head><body></body></html>
        """
        let scraped = stripHTMLLikeImportService(shellHTML)
        XCTAssertLessThan(scraped.count, 40, "TikTok shell scrape must stay below validation threshold")
    }

    @MainActor
    func testTikTokShellWithoutOEmbed_returnsUseHTMLScrape() async throws {
        MockURLProtocol.register(matching: { $0.url?.host?.contains("tiktok.com") == true }) { req in
            let html = "<html><head><title>TikTok - Make Your Day</title></head><body></body></html>"
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(html.utf8))
        }

        let result = try await SocialURLRouter.route(url: userURL, session: session)
        XCTAssertEqual(result, .useHTMLScrape)
    }

    // MARK: - Fixes

    @MainActor
    func testReflowHTML_passesImportValidation() async throws {
        registerReflowHTML(caption: cajunCaption)

        let result = try await SocialURLRouter.route(url: userURL, session: session)
        try assertPassingImportContext(from: result)
    }

    @MainActor
    func testOEmbedFallbackWhenHTMLShell_passesImportValidation() async throws {
        registerTikTokMocks(pageHTML: "<html><title>TikTok - Make Your Day</title></html>", oEmbedJSON: oEmbedJSON)

        let result = try await SocialURLRouter.route(url: userURL, session: session)
        try assertPassingImportContext(from: result, containing: "cajun pasta")
    }

    @MainActor
    func testUserReportedURL_usesOEmbedWhenRehydrationMissing() async throws {
        registerTikTokMocks(pageHTML: "<html><body>TikTok shell</body></html>", oEmbedJSON: oEmbedJSON)

        let result = try await SocialURLRouter.route(url: userURL, session: session)
        try assertPassingImportContext(from: result, containing: "chicken")
    }

    @MainActor
    func testFetchTikTokOEmbed_parsesAuthorAndCaption() async throws {
        MockURLProtocol.register(matching: { $0.url?.path == "/oembed" }) { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(self.oEmbedJSON.utf8))
        }

        let parsed = await SocialURLRouter.fetchTikTokOEmbed(for: userURL, session: session)
        XCTAssertEqual(parsed?.authorName, "Viral Recipes")
        XCTAssertTrue(parsed?.caption.contains("cajun pasta") == true)
    }

    // MARK: - Helpers

    private func registerReflowHTML(caption: String) {
        MockURLProtocol.register(matching: { $0.url?.host?.contains("tiktok.com") == true && $0.url?.path != "/oembed" }) { req in
            let escaped = caption.replacingOccurrences(of: "\"", with: "\\\"")
            let html = """
            <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{
              "__DEFAULT_SCOPE__": {
                "webapp.reflow.video.detail": {
                  "itemInfo": { "itemStruct": { "desc": "\(escaped)" } }
                }
              }
            }</script>
            """
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(html.utf8))
        }
    }

    private func registerTikTokMocks(pageHTML: String, oEmbedJSON: String) {
        MockURLProtocol.register(matching: { $0.url?.path == "/oembed" }) { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(oEmbedJSON.utf8))
        }
        MockURLProtocol.register(matching: { $0.url?.host?.contains("tiktok.com") == true && $0.url?.path != "/oembed" }) { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(pageHTML.utf8))
        }
    }

    private func assertPassingImportContext(
        from result: SocialURLResult,
        containing needle: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case .recipeText(let context) = result else {
            XCTFail("Expected .recipeText, got \(result)", file: file, line: line)
            return
        }
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40, file: file, line: line)
        if let needle {
            XCTAssertTrue(
                context.cleanedText.localizedCaseInsensitiveContains(needle),
                file: file,
                line: line
            )
        }
        XCTAssertNoThrow(try validateImportText(context.cleanedText), file: file, line: line)
    }

    private func validateImportText(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else {
            throw ImportError.insufficientContent
        }
    }

    private func stripHTMLLikeImportService(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
