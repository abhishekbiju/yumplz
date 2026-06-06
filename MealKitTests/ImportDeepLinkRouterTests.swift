import XCTest
@testable import MealKit

final class ImportDeepLinkRouterTests: XCTestCase {

    func testRoute_youTubeShortURL_autoStartsImport() {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        let userInfo: [String: Any] = [
            MealKitImportDeepLinkUserInfoKey.autoStart: true,
            MealKitImportDeepLinkUserInfoKey.extractionMode: ShareExtractionMode.captionOrDescription.rawValue,
        ]

        let route = ImportDeepLinkRouter.route(payload: url, userInfo: userInfo)

        XCTAssertEqual(route.importURL, url)
        XCTAssertNil(route.pasteText)
        XCTAssertNil(route.videoPath)
        XCTAssertTrue(route.autoStartImport)
    }

    func testRoute_videoFilePath() {
        let payload = "file:///group/videos/clip.mp4"
        let route = ImportDeepLinkRouter.route(
            payload: payload,
            userInfo: [MealKitImportDeepLinkUserInfoKey.autoStart: true]
        )

        XCTAssertEqual(route.videoPath, "/group/videos/clip.mp4")
        XCTAssertNil(route.importURL)
        XCTAssertTrue(route.autoStartImport)
    }

    func testRoute_plainText_notURL() {
        let text = "Mix 2 cups flour with 1 cup water and bake at 350F for 30 minutes until golden."
        let route = ImportDeepLinkRouter.route(payload: text, userInfo: nil)

        XCTAssertEqual(route.pasteText, text)
        XCTAssertNil(route.importURL)
        XCTAssertFalse(route.autoStartImport)
    }
}
