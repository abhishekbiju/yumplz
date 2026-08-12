import XCTest
@testable import Yumplz

final class ShareImportDeliveryNotificationTests: XCTestCase {

    private var sharedDir: URL!

    override func setUp() {
        super.setUp()
        sharedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareImportDeliveryNotification-\(UUID().uuidString)", isDirectory: true)
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

    func testDeliverPendingImports_postsDeepLinkNotification() {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        PendingImportStore.append(PendingImportItem(kind: .url, value: url, autoStartImport: true))

        let exp = expectation(description: "deep link posted")
        var received: String?
        let token = NotificationCenter.default.addObserver(
            forName: .yumplzImportDeepLink,
            object: nil,
            queue: nil
        ) { note in
            received = note.object as? String
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        ShareImportDelivery.deliverPendingImports()

        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(received, url)
        XCTAssertFalse(PendingImportStore.hasPending)
    }
}
