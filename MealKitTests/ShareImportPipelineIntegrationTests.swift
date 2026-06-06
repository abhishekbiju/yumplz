import XCTest
@testable import MealKit

/// End-to-end simulation: Share Extension queues → app drains → deep link route → import source.
final class ShareImportPipelineIntegrationTests: XCTestCase {

    private var session: URLSession!
    private var sharedDir: URL!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = .mockEphemeral
        sharedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareImportPipeline-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        PendingImportStore.useContainerDirectory(sharedDir)
        PendingImportStore.drain()
    }

    override func tearDown() {
        PendingImportStore.drain()
        PendingImportStore.resetContainerDirectoryOverride()
        MockURLProtocol.reset()
        session = nil
        try? FileManager.default.removeItem(at: sharedDir)
        super.tearDown()
    }

    func testShareExtensionToImportPipeline_youTubeShort() async throws {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        let description = "Garlic butter pasta: boil spaghetti, sauté garlic in butter, toss with parmesan."

        // 1. Share Extension queues the URL.
        PendingImportStore.append(PendingImportItem(kind: .url, value: url, autoStartImport: true))

        // 2. Main app drains on appear.
        let deliveries = ShareImportDelivery.drainAndDeliver()
        XCTAssertEqual(deliveries.count, 1)

        // 3. Library routes the deep link.
        let note = ShareImportDelivery.makeDeepLinkNotification(for: PendingImportItem(
            kind: deliveries[0].importKind,
            value: url,
            autoStartImport: deliveries[0].autoStartImport
        ))
        let route = ImportDeepLinkRouter.route(payload: note.object, userInfo: note.userInfo)
        XCTAssertEqual(route.importURL, url)
        XCTAssertTrue(route.autoStartImport)

        // 4. SocialURLRouter extracts recipe text (mocked).
        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("/shorts/") == true }) { req in
            let html = """
            <html><body><script>var ytInitialPlayerResponse = {"videoDetails":{"shortDescription":"\(description)"}};</script></body></html>
            """
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(html.utf8))
        }
        MockURLProtocol.register(matching: { $0.url?.absoluteString.contains("timedtext") == true }) { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        guard let importURL = URL(string: url) else {
            return XCTFail("Invalid URL")
        }
        let socialResult = try await SocialURLRouter.route(url: importURL, session: session)
        guard case .recipeText(let context) = socialResult else {
            return XCTFail("Expected recipeText extraction, got \(socialResult)")
        }
        let extracted = context.cleanedText
        XCTAssertTrue(extracted.contains("garlic"))
        XCTAssertGreaterThanOrEqual(extracted.count, 40)
    }
}
