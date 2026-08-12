import XCTest
@testable import Yumplz

final class ImportLinkParserTests: XCTestCase {

    func testImportableURL_acceptsYouTubeShorts() {
        let url = ImportLinkParser.importableURL(from: "https://www.youtube.com/shorts/6UuseD5McGE")
        XCTAssertEqual(url?.absoluteString, "https://www.youtube.com/shorts/6UuseD5McGE")
    }

    func testImportableURL_acceptsYouTubeWatch() {
        let url = ImportLinkParser.importableURL(from: "https://www.youtube.com/watch?v=abc123")
        XCTAssertNotNil(url)
    }

    func testImportableURL_rejectsPlainText() {
        XCTAssertNil(ImportLinkParser.importableURL(from: "just some recipe text"))
    }

    func testImportableURL_trimsWhitespace() {
        let url = ImportLinkParser.importableURL(from: "  https://youtu.be/xyz  ")
        XCTAssertEqual(url?.host, "youtu.be")
    }

    func testSocialPlatformDetector_youtubeShorts() {
        let url = URL(string: "https://www.youtube.com/shorts/6UuseD5McGE")!
        XCTAssertEqual(SocialPlatformDetector.platform(for: url), .youtube)
        XCTAssertEqual(SocialPlatformDetector.displayName(for: .youtube), "YouTube")
    }
}
