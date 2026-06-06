import XCTest
@testable import MealKit

final class ImportPresentationRequestTests: XCTestCase {

    func testPresentationRequest_preservesRouteForSheetBinding() {
        let url = "https://www.youtube.com/shorts/6UuseD5McGE"
        let route = ImportDeepLinkRouter.route(
            payload: url,
            userInfo: [MealKitImportDeepLinkUserInfoKey.autoStart: true]
        )
        let request = ImportPresentationRequest(route: route)

        XCTAssertEqual(request.route.importURL, url)
        XCTAssertTrue(request.route.autoStartImport)
        XCTAssertNotNil(request.id)
    }
}
