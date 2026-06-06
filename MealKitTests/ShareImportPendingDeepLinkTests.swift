import XCTest
@testable import MealKit

final class ShareImportPendingDeepLinkTests: XCTestCase {

    override func tearDown() {
        _ = ShareImportDelivery.consumePendingDeepLink()
        super.tearDown()
    }

    func testStoreAndConsumePendingDeepLink_survivesColdLaunch() {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        ShareImportDelivery.storePendingDeepLink(
            payload: url,
            userInfo: [MealKitImportDeepLinkUserInfoKey.autoStart: true]
        )

        let consumed = ShareImportDelivery.consumePendingDeepLink()

        XCTAssertEqual(consumed?.route.importURL, url)
        XCTAssertTrue(consumed?.route.autoStartImport == true)
        XCTAssertNil(ShareImportDelivery.consumePendingDeepLink())
    }

    func testClearPendingDeepLink_discardsReplay() {
        ShareImportDelivery.storePendingDeepLink(
            payload: "https://www.youtube.com/shorts/6UuseD5McGE",
            userInfo: [MealKitImportDeepLinkUserInfoKey.autoStart: true]
        )

        XCTAssertTrue(ShareImportDelivery.hasPendingDeepLink)
        ShareImportDelivery.clearPendingDeepLink()
        XCTAssertFalse(ShareImportDelivery.hasPendingDeepLink)
        XCTAssertNil(ShareImportDelivery.consumePendingDeepLink())
    }
}
