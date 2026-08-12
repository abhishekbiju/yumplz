import XCTest
@testable import Yumplz

/// Integration tests that simulate Share Extension → `PendingImportStore` → `SocialURLRouter`
/// using mocked HTTP responses (no live TikTok/YouTube calls).
final class SocialURLRouterIntegrationTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = .mockEphemeral
        PendingImportStore.drain()
    }

    override func tearDown() {
        PendingImportStore.drain()
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private static let longRecipeCaption = """
    Ingredients: 2 cups flour, 1 tsp yeast, 1 cup warm water, 1 tbsp olive oil, 1 tsp salt. \
    Mix dry ingredients, add water and oil, knead 10 minutes until smooth. \
    Rise 1 hour until doubled. Shape into loaf, bake at 220C for 35 minutes until golden. \
    Cool before slicing. Perfect homemade bread for beginners every single time.
    """

    private static let thinCaption = "Full recipe on my blog - link in bio"

    private func timedtextJSON(transcript: String) -> Data {
        let segs = transcript.split(separator: " ").map { ["utf8": "\($0) "] }
        let payload: [String: Any] = ["events": [["segs": segs]]]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private func tiktokHTML(
        caption: String,
        audioURL: String? = "https://cdn.tiktok.com/audio/sample.m4a",
        bioLink: String? = "https://chef.example.com/sourdough"
    ) -> Data {
        let escaped = caption.replacingOccurrences(of: "\"", with: "\\\"")
        var structFields = [#""desc": "\#(escaped)""#]
        if let audioURL {
            structFields.append(#""music": { "playUrl": "\#(audioURL)" }"#)
        }
        if let bioLink {
            structFields.append(#""author": { "bioLink": { "link": "\#(bioLink)" } }"#)
        }
        let fields = structFields.joined(separator: ",\n                  ")
        let html = """
        <!DOCTYPE html><html><head>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{
          "DEFAULT_SCOPE": {
            "webapp.video-detail": {
              "itemInfo": {
                "itemStruct": {
                  \(fields)
                }
              }
            }
          }
        }</script>
        </head><body></body></html>
        """
        return Data(html.utf8)
    }

    private func tiktokReflowHTML(caption: String) -> Data {
        let escaped = caption.replacingOccurrences(of: "\"", with: "\\\"")
        let html = """
        <!DOCTYPE html><html><head>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{
          "__DEFAULT_SCOPE__": {
            "webapp.reflow.video.detail": {
              "itemInfo": {
                "itemStruct": {
                  "desc": "\(escaped)",
                  "music": { "playUrl": "https://cdn.tiktok.com/audio/reflow.m4a" }
                }
              }
            }
          }
        }</script>
        </head><body></body></html>
        """
        return Data(html.utf8)
    }

    private func youtubePageHTML(description: String) -> Data {
        let html = """
        <html><head>
        <meta property="og:description" content="\(description)" />
        </head><body></body></html>
        """
        return Data(html.utf8)
    }

    private func youtubeShortsPageHTML(shortDescription: String) -> Data {
        let escaped = shortDescription.replacingOccurrences(of: "\"", with: "\\\"")
        let html = """
        <html><head></head><body>
        <script>var ytInitialPlayerResponse = {"videoDetails":{"shortDescription":"\(escaped)"}};</script>
        </body></html>
        """
        return Data(html.utf8)
    }

    private func recipeBlogHTML() -> Data {
        let html = """
        <html><body>
        <h1>Sourdough Loaf</h1>
        <p>Mix flour yeast water salt knead rise bake enjoy warm bread with butter.</p>
        </body></html>
        """
        return Data(html.utf8)
    }

  private func okResponse(for request: URLRequest, data: Data) -> (HTTPURLResponse, Data) {
    let url = request.url ?? URL(string: "https://example.com")!
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (response, data)
  }

    // MARK: - YouTube URL cases (share-extension style)

    @MainActor
    func testRouteYouTubeWatchURL_returnsTimedtextTranscript() async throws {
        let videoID = "recipeWatch123"
        let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        let transcript = "Add flour to bowl then pour warm water and mix until smooth dough forms"

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            self.okResponse(for: req, data: self.timedtextJSON(transcript: transcript))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)

        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("flour"))
    }

    @MainActor
    func testRouteYouTubeShortURL_returnsTimedtextTranscript() async throws {
        let videoID = "shortVid99"
        let url = URL(string: "https://youtu.be/\(videoID)")!
        let transcript = "Sauté garlic in olive oil add tomatoes simmer twenty minutes serve over pasta"

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            self.okResponse(for: req, data: self.timedtextJSON(transcript: transcript))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)

        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("pasta"))
    }

    @MainActor
    func testRouteYouTubeShortsURL_returnsTimedtextTranscript() async throws {
        let videoID = "shortsRecipe42"
        let url = URL(string: "https://www.youtube.com/shorts/\(videoID)")!
        XCTAssertEqual(SocialURLRouter.extractYouTubeVideoID(from: url), videoID)

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            self.okResponse(for: req, data: self.timedtextJSON(transcript: "Whisk eggs milk flour cook pancakes on medium heat"))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("pancakes"))
    }

    @MainActor
    func testRouteYouTubeShortsURL_usesInlineDescriptionWhenTimedtextEmpty() async throws {
        let videoID = "6UuseD5McGE"
        let url = URL(string: "https://www.youtube.com/shorts/\(videoID)")!
        let description = "Easy garlic butter pasta: boil spaghetti, sauté minced garlic in butter, toss with parmesan and parsley, serve hot."

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("/shorts/") == true }) { req in
            self.okResponse(for: req, data: self.youtubeShortsPageHTML(shortDescription: description))
        }
        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            self.okResponse(for: req, data: Data("{}".utf8))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("garlic"))
    }

    @MainActor
    func testExtractYouTubeInlineDescription_parsesShortDescriptionJSON() {
        let data = youtubeShortsPageHTML(shortDescription: "Mix flour yeast water knead rise bake fresh bread at home easily")
        let html = String(decoding: data, as: UTF8.self)
        let text = SocialURLRouter.extractYouTubeInlineDescription(from: html)
        XCTAssertTrue(text?.contains("flour") == true)
    }

    @MainActor
    func testRouteYouTubeFallsBackToMetaDescriptionWhenTimedtextEmpty() async throws {
        let url = URL(string: "https://www.youtube.com/watch?v=metaFallback1")!
        let description = "One pot chicken rice recipe with turmeric cumin and fresh cilantro garnish"

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            self.okResponse(for: req, data: Data("{}".utf8))
        }
        MockURLProtocol.register(matching: { req in
            guard let host = req.url?.host else { return false }
            return host.contains("youtube.com") && req.url?.path.contains("watch") == true
        }) { req in
            self.okResponse(for: req, data: self.youtubePageHTML(description: description))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("chicken"))
    }

    // MARK: - TikTok URL cases

    @MainActor
    func testRouteTikTokReflowPage_returnsMediumCaption() async throws {
        let url = URL(string:
            "https://www.tiktok.com/@recipes/video/7312508978880154888?is_from_webapp=1&sender_device=pc"
        )!
        let caption = """
        You guys need to try this creamy chicken cajun pasta. This pasta recipe is your ticket \
        to a quick dinner solution. It is a one pan meal, ideal for those busy weeknights. \
        What pasta should we make next?
        """

        MockURLProtocol.register(matching: { req in
            req.url?.host?.contains("tiktok.com") == true
        }) { req in
            self.okResponse(for: req, data: self.tiktokReflowHTML(caption: caption))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        XCTAssertTrue(context.cleanedText.contains("cajun pasta"))
        XCTAssertGreaterThanOrEqual(context.cleanedText.count, 40)
    }

    @MainActor
    func testRouteTikTokFullVideoURL_returnsLongCaption() async throws {
        let url = URL(string: "https://www.tiktok.com/@homebaker/video/7123456789012345678")!

        MockURLProtocol.register(matching: { $0.url?.host?.contains("tiktok.com") == true }) { req in
            self.okResponse(for: req, data: self.tiktokHTML(caption: Self.longRecipeCaption))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("flour"))
        XCTAssertGreaterThan(text.split(separator: " ").count, 40)
    }

    @MainActor
    func testRouteTikTokVMShortLink_returnsLongCaption() async throws {
        let url = URL(string: "https://vm.tiktok.com/ZMRecipeLink99/")!

        MockURLProtocol.register(matching: { $0.url?.host?.contains("tiktok.com") == true }) { req in
            self.okResponse(for: req, data: self.tiktokHTML(caption: Self.longRecipeCaption))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("yeast"))
    }

    @MainActor
    func testRouteTikTokThinCaption_scrapesBioLink() async throws {
        let url = URL(string: "https://www.tiktok.com/@chef/video/7999999999999999999")!

        MockURLProtocol.register(matching: { req in
            guard let host = req.url?.host else { return false }
            return host.contains("tiktok.com")
        }) { req in
            self.okResponse(for: req, data: self.tiktokHTML(caption: Self.thinCaption))
        }

        MockURLProtocol.register(matching: { $0.url?.host == "chef.example.com" }) { req in
            self.okResponse(for: req, data: self.recipeBlogHTML())
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.localizedCaseInsensitiveContains("sourdough"))
    }

    @MainActor
    func testRouteTikTokThinCaptionNoBio_fallsBackToOEmbed() async throws {
        let url = URL(string: "https://www.tiktok.com/@chef/video/7888888888888888888")!

        MockURLProtocol.register(matching: { $0.url?.path == "/oembed" }) { req in
            let json = """
            {"title":"Full sourdough recipe with starter tips and overnight rise instructions.","author_name":"Chef"}
            """
            return self.okResponse(for: req, data: Data(json.utf8))
        }
        MockURLProtocol.register(matching: { req in
            (req.url?.host?.contains("tiktok.com") == true) && req.url?.path != "/oembed"
        }) { req in
            self.okResponse(
                for: req,
                data: self.tiktokHTML(caption: Self.thinCaption, audioURL: nil, bioLink: nil)
            )
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        XCTAssertTrue(context.cleanedText.localizedCaseInsensitiveContains("sourdough"))
    }

    // MARK: - Share Extension pipeline simulation

    @MainActor
    func testShareExtensionPipeline_YouTubeURLQueuedThenRouted() async throws {
        let sharedURL = "https://www.youtube.com/watch?v=shareExtYt1"
        PendingImportStore.append(PendingImportItem(kind: .url, value: sharedURL))

        let pending = PendingImportStore.drain()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.kind, .url)

        let url = URL(string: pending[0].value)!
        XCTAssertEqual(SocialURLRouter.platform(for: url), .youtube)

        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            self.okResponse(for: req, data: self.timedtextJSON(transcript: "Layer lasagna noodles ricotta mozzarella bake until bubbling"))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("lasagna"))
    }

    @MainActor
    func testShareExtensionPipeline_TikTokURLQueuedThenRouted() async throws {
        let sharedURL = "https://vm.tiktok.com/ZMShareRecipe01/"
        PendingImportStore.append(PendingImportItem(kind: .url, value: sharedURL))

        let pending = PendingImportStore.drain()
        XCTAssertEqual(pending.count, 1)

        let url = URL(string: pending[0].value)!
        XCTAssertEqual(SocialURLRouter.platform(for: url), .tiktok)

        MockURLProtocol.register(matching: { $0.url?.host?.contains("tiktok.com") == true }) { req in
            self.okResponse(for: req, data: self.tiktokHTML(caption: Self.longRecipeCaption))
        }

        let result = try await SocialURLRouter.route(url: url, session: session)
        guard case .recipeText(let context) = result else {
            return XCTFail("Expected .recipeText, got \(result)")
        }
        let text = context.cleanedText
        XCTAssertTrue(text.contains("bread"))
    }

    @MainActor
    func testShareExtensionPipeline_InstagramURLReturnsNeedsVideoFile() async throws {
        let sharedURL = "https://www.instagram.com/reel/CxRecipe123/"
        PendingImportStore.append(PendingImportItem(kind: .url, value: sharedURL))

        let url = URL(string: PendingImportStore.drain()[0].value)!
        let result = try await SocialURLRouter.route(url: url, session: session)
        XCTAssertEqual(result, .needsVideoFile)
    }
}
