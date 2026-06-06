import XCTest
@testable import MealKit

/// TDD slices for `SocialURLRouter` — red → green, one behaviour at a time.
/// All 8 tests exercise pure parsing/detection logic; no network calls are made.
final class SocialURLRouterTests: XCTestCase {

    // MARK: – Slice 1 · TikTok platform detection

    func testPlatformDetectionTikTok() {
        let url = URL(string: "https://vm.tiktok.com/ZMF12345/")!
        XCTAssertEqual(SocialURLRouter.platform(for: url), .tiktok)
    }

    // MARK: – Slice 2 · YouTube platform detection

    func testPlatformDetectionYouTube() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(SocialURLRouter.platform(for: url), .youtube)
    }

    // MARK: – Slice 3 · Instagram platform detection

    func testPlatformDetectionInstagram() {
        let url = URL(string: "https://www.instagram.com/reel/C12345/")!
        XCTAssertEqual(SocialURLRouter.platform(for: url), .instagram)
    }

    // MARK: – Slice 4 · Other platform detection

    func testPlatformDetectionOther() {
        let url = URL(string: "https://www.allrecipes.com/recipe/12345/chicken-soup/")!
        XCTAssertEqual(SocialURLRouter.platform(for: url), .other)
    }

    // MARK: – Slice 5 · YouTube video ID from watch URL

    func testExtractYouTubeVideoID() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        XCTAssertEqual(SocialURLRouter.extractYouTubeVideoID(from: url), "dQw4w9WgXcQ")
    }

    // MARK: – Slice 6 · YouTube video ID from short URL

    func testExtractYouTubeVideoIDShortURL() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        XCTAssertEqual(SocialURLRouter.extractYouTubeVideoID(from: url), "dQw4w9WgXcQ")
    }

    func testExtractYouTubeVideoIDFromShortsURL() {
        let url = URL(string: "https://www.youtube.com/shorts/abcShorts99")!
        XCTAssertEqual(SocialURLRouter.extractYouTubeVideoID(from: url), "abcShorts99")
    }

    // MARK: – Slice 7 · Parse YouTube timedtext JSON

    func testParseTimedtextJSON() {
        // Minimal youtube timedtext fmt=json3 fixture with multiple segment objects.
        let fixture = """
        {
          "events": [
            { "segs": [{"utf8": "Mix"},  {"utf8": " the"}] },
            { "segs": [{"utf8": " flour"}, {"utf8": " and"}, {"utf8": " water"}] },
            { "segs": [{"utf8": " until"}, {"utf8": " combined"}] }
          ]
        }
        """
        let data = fixture.data(using: .utf8)!
        let result = SocialURLRouter.parseTimedtextJSON(data)

        XCTAssertTrue(result.contains("Mix"), "Should contain first segment text")
        XCTAssertTrue(result.contains("flour"), "Should contain second segment text")
        XCTAssertTrue(result.contains("combined"), "Should contain last segment text")
        XCTAssertFalse(result.isEmpty, "Result should not be empty")
    }

    // MARK: – Slice 8 · Parse TikTok rehydration JSON from HTML fixture

    func testParseTikTokRehydrationJSON() {
        let expectedCaption = "Making the best sourdough bread at home using a simple starter recipe."
        let expectedAudioURL = "https://cdn.tiktok.com/audio/sample12345.m4a"
        let expectedBioLink  = "https://example.com/my-recipe-blog"

        // Minimal HTML page embedding the rehydration script tag with the
        // required JSON key path: DEFAULT_SCOPE → webapp.video-detail → itemInfo → itemStruct
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{
          "DEFAULT_SCOPE": {
            "webapp.video-detail": {
              "itemInfo": {
                "itemStruct": {
                  "desc": "\(expectedCaption)",
                  "music": {
                    "playUrl": "\(expectedAudioURL)"
                  },
                  "author": {
                    "bioLink": {
                      "link": "\(expectedBioLink)"
                    }
                  }
                }
              }
            }
          }
        }</script>
        </head>
        <body></body>
        </html>
        """

        let (desc, audioURL, bioLink) = SocialURLRouter.parseTikTokRehydrationHTML(html)

        XCTAssertEqual(desc, expectedCaption,  "desc should match itemStruct.desc")
        XCTAssertEqual(audioURL?.absoluteString, expectedAudioURL, "audioURL should match music.playUrl")
        XCTAssertEqual(bioLink?.absoluteString,  expectedBioLink,  "bioLink should match author.bioLink.link")
    }

    func testParseTikTokRehydrationJSON_reflowPageScope() {
        let expectedCaption = """
        You guys need to try this creamy chicken cajun pasta. This pasta recipe is your ticket \
        to a quick dinner solution. It is a one pan meal, ideal for those busy weeknights.
        """
        let html = """
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{
          "__DEFAULT_SCOPE__": {
            "webapp.reflow.video.detail": {
              "itemInfo": {
                "itemStruct": {
                  "desc": "\(expectedCaption)",
                  "music": { "playUrl": "https://cdn.tiktok.com/audio/reflow.m4a" }
                }
              }
            }
          }
        }</script>
        """

        let (desc, audioURL, _) = SocialURLRouter.parseTikTokRehydrationHTML(html)

        XCTAssertEqual(desc, expectedCaption)
        XCTAssertEqual(audioURL?.absoluteString, "https://cdn.tiktok.com/audio/reflow.m4a")
    }

    func testCanonicalTikTokURLStripsTrackingQueryParams() {
        let url = URL(string:
            "https://www.tiktok.com/@recipes/video/7312508978880154888?is_from_webapp=1&sender_device=pc"
        )!
        let canonical = SocialURLRouter.canonicalTikTokURL(url)
        XCTAssertEqual(
            canonical.absoluteString,
            "https://www.tiktok.com/@recipes/video/7312508978880154888"
        )
    }

    func testSubstantiveRecipeText_acceptsMediumCaptions() {
        let caption = String(repeating: "word ", count: 30)
        XCTAssertTrue(SocialURLRouter.isSubstantiveRecipeText(caption, wordCount: 30))
    }
}
