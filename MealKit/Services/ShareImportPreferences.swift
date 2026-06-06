import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// How the main app should extract recipe text from a share-extension import.
enum ShareExtractionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Social caption / YouTube description / TikTok caption (default for links).
    case captionOrDescription
    /// Skip social routing and scrape the full webpage (recipe blogs).
    case fullPage
    /// Transcribe audio from a shared video file (Whisper, on-device).
    case transcribeAudio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .captionOrDescription: return "Caption / description"
        case .fullPage: return "Full webpage"
        case .transcribeAudio: return "Transcribe video"
        }
    }

    var detail: String {
        switch self {
        case .captionOrDescription:
            return "Best for YouTube, TikTok, and Shorts — reads the post text."
        case .fullPage:
            return "Best for recipe blogs — reads the whole page."
        case .transcribeAudio:
            return "Listens to the video audio on your device."
        }
    }

    /// Modes available for a given share payload.
    static func options(for content: ShareContentKind) -> [ShareExtractionMode] {
        switch content {
        case .webURL(let platform):
            switch platform {
            case .youtube, .tiktok, .instagram:
                return [.captionOrDescription, .fullPage]
            case .other:
                return [.fullPage, .captionOrDescription]
            }
        case .videoFile:
            return [.transcribeAudio]
        case .plainText:
            return [.captionOrDescription]
        }
    }
}

enum ShareContentKind: Equatable, Sendable {
    case webURL(platform: SocialPlatform)
    case videoFile
    case plainText
}

/// User choices made in the Share Extension before queuing an import.
struct ShareImportPreferences: Codable, Sendable, Equatable {
    var extractionMode: ShareExtractionMode
    var autoStartImport: Bool
    var openAppAfterQueue: Bool

    static let `default` = ShareImportPreferences(
        extractionMode: .captionOrDescription,
        autoStartImport: true,
        openAppAfterQueue: true
    )
}

/// Opens the containing app from the Share Extension.
enum ShareAppLauncher {

    /// Deep link that carries the shared URL/text so import works even if the App Group queue is empty.
    static func importDeepLinkURL(for text: String, autoStart: Bool = true) -> URL? {
        var components = URLComponents()
        components.scheme = "mealkit"
        components.host = "import"
        // Encode the payload ourselves: shared URLs frequently contain `?`, `&`, and
        // `=` (e.g. Instagram `?igsh=…`). URLComponents.queryItems leaves those
        // sub-delimiters un-encoded inside a value, which corrupts the round-trip.
        // Percent-encoding everything but alphanumerics keeps the payload intact.
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        components.percentEncodedQuery = "text=\(encoded)&autostart=\(autoStart ? "1" : "0")"
        return components.url
    }

    /// Minimal deep link that only foregrounds MealKit (queue must already hold the import).
    static var launchURL: URL {
        var components = URLComponents()
        components.scheme = "mealkit"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "launch", value: "1")]
        return components.url!
    }
}
