import XCTest
@testable import MealKit

final class ShareImportPreferencesTests: XCTestCase {

    func testLaunchURLUsesMealkitScheme() {
        let url = ShareImportDelivery.launchURL
        XCTAssertEqual(url.scheme, "mealkit")
        XCTAssertEqual(url.host, "import")
        XCTAssertEqual(url.query, "launch=1")
    }

    func testPendingImportItemRoundTripsWithPreferences() throws {
        let item = PendingImportItem(
            kind: .url,
            value: "https://www.youtube.com/shorts/6UuseD5McGE",
            extractionMode: .fullPage,
            autoStartImport: true
        )
        PendingImportStore.append(item)

        let data = try Data(contentsOf: PendingImportStore.pendingFileURL)
        let decoded = try JSONDecoder().decode([PendingImportItem].self, from: data).first

        XCTAssertEqual(decoded?.extractionMode, .fullPage)
        XCTAssertEqual(decoded?.autoStartImport, true)
    }

    func testShareExtractionModeOptionsForYouTube() {
        let modes = ShareExtractionMode.options(for: .webURL(platform: .youtube))
        XCTAssertTrue(modes.contains(.captionOrDescription))
        XCTAssertTrue(modes.contains(.fullPage))
    }
}
