import XCTest
@testable import Yumplz

/// Tests the share-extension → main-app handoff through public store + delivery APIs.
final class ShareImportDeliveryTests: XCTestCase {

    private var sharedDir: URL!

    override func setUp() {
        super.setUp()
        sharedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareImportDeliveryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        PendingImportStore.useContainerDirectory(sharedDir)
        PendingImportStore.drain()
    }

    override func tearDown() {
        PendingImportStore.drain()
        PendingImportStore.resetContainerDirectoryOverride()
        try? FileManager.default.removeItem(at: sharedDir)
        super.tearDown()
    }

    // MARK: - Queue visibility (simulates extension + app sharing App Group dir)

    func testQueuedYouTubeShortIsVisibleAfterAppend() {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        PendingImportStore.append(PendingImportItem(kind: .url, value: url))

        XCTAssertTrue(PendingImportStore.hasPending)
        XCTAssertEqual(PendingImportStore.readAll().first?.value, url)
    }

    func testDrainAndDeliver_youTubeShort_autoStartsURLImport() {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        PendingImportStore.append(PendingImportItem(kind: .url, value: url, autoStartImport: true))

        let deliveries = ShareImportDelivery.drainAndDeliver()

        XCTAssertEqual(deliveries.count, 1)
        XCTAssertEqual(deliveries[0].payload, url)
        XCTAssertTrue(deliveries[0].autoStartImport)
        XCTAssertEqual(deliveries[0].importKind, .url)
        XCTAssertEqual(deliveries[0].extractionMode, .captionOrDescription)
        XCTAssertFalse(PendingImportStore.hasPending)
    }

    func testDrainAndDeliver_emptyQueueReturnsEmpty() {
        XCTAssertTrue(ShareImportDelivery.drainAndDeliver().isEmpty)
    }

    func testPayloadString_videoFileUsesFileScheme() {
        let item = PendingImportItem(kind: .videoFile, value: "/group/videos/clip.mp4")
        XCTAssertEqual(ShareImportDelivery.payloadString(for: item), "file:///group/videos/clip.mp4")
    }

    func testLaunchURL_usesYumplzImportLaunchQuery() {
        let url = ShareImportDelivery.launchURL
        XCTAssertEqual(url.scheme, "yumplz")
        XCTAssertEqual(url.host, "import")
        XCTAssertTrue(url.query?.contains("launch=1") == true)
    }

    func testMakeDeepLinkNotification_youTubeShort() {
        let item = PendingImportItem(
            kind: .url,
            value: "https://www.youtube.com/shorts/abc123",
            autoStartImport: true
        )
        let note = ShareImportDelivery.makeDeepLinkNotification(for: item)

        XCTAssertEqual(note.name, .yumplzImportDeepLink)
        XCTAssertEqual(note.object, item.value)
        XCTAssertEqual(note.userInfo[YumplzImportDeepLinkUserInfoKey.autoStart] as? Bool, true)
        XCTAssertEqual(
            note.userInfo[YumplzImportDeepLinkUserInfoKey.extractionMode] as? String,
            ShareExtractionMode.captionOrDescription.rawValue
        )
    }

    /// Regression: cold launch can skip scenePhase onChange — delivery must work whenever called.
    func testDrainAndDeliver_canBeCalledMultipleTimesSafely() {
        PendingImportStore.append(PendingImportItem(kind: .url, value: "https://youtu.be/abc"))

        let first = ShareImportDelivery.drainAndDeliver()
        let second = ShareImportDelivery.drainAndDeliver()

        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
    }
}
