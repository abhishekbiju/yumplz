import XCTest
@testable import MealKit

final class ShareAppLauncherTests: XCTestCase {

    func testImportDeepLinkURL_embedsSharedTextAndAutoStart() throws {
        let url = try XCTUnwrap(ShareAppLauncher.importDeepLinkURL(
            for: "https://www.youtube.com/shorts/6UuseD5McGE",
            autoStart: true
        ))
        XCTAssertEqual(url.scheme, "mealkit")
        XCTAssertEqual(url.host, "import")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let text = components.queryItems?.first(where: { $0.name == "text" })?.value
        let autostart = components.queryItems?.first(where: { $0.name == "autostart" })?.value

        XCTAssertEqual(text, "https://www.youtube.com/shorts/6UuseD5McGE")
        XCTAssertEqual(autostart, "1")
    }

    func testImportDeepLinkURL_roundTripsThroughRootViewParser() throws {
        let shared = "https://www.youtube.com/shorts/abc123"
        let url = try XCTUnwrap(ShareAppLauncher.importDeepLinkURL(for: shared, autoStart: true))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        let text = components.queryItems?.first(where: { $0.name == "text" })?.value
        let autoStart = components.queryItems?.first(where: { $0.name == "autostart" })?.value != "0"

        let route = ImportDeepLinkRouter.route(
            payload: text ?? "",
            userInfo: [MealKitImportDeepLinkUserInfoKey.autoStart: autoStart]
        )

        XCTAssertEqual(route.importURL, shared)
        XCTAssertTrue(route.autoStartImport)
    }

    /// Regression: real share URLs carry query params (`?igsh=…&utm=…`). The deep
    /// link must percent-encode the payload so `&`/`?`/`=` don't corrupt parsing.
    func testImportDeepLinkURL_preservesURLsContainingQueryParameters() throws {
        let shared = "https://www.instagram.com/reel/AbC123/?igsh=ZZZ123&utm_source=ig"
        let url = try XCTUnwrap(ShareAppLauncher.importDeepLinkURL(for: shared, autoStart: true))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        let text = components.queryItems?.first(where: { $0.name == "text" })?.value
        let autoStart = components.queryItems?.first(where: { $0.name == "autostart" })?.value != "0"

        XCTAssertEqual(text, shared, "Embedded URL with query params must survive the round-trip intact")
        XCTAssertTrue(autoStart)

        let route = ImportDeepLinkRouter.route(
            payload: text ?? "",
            userInfo: [MealKitImportDeepLinkUserInfoKey.autoStart: autoStart]
        )
        XCTAssertEqual(route.importURL, shared)
    }
}
