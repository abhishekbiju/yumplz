import Foundation

/// Shared platform detection for import URLs (main app + Share Extension).
enum SocialPlatform: Equatable, Sendable {
    case tiktok
    case youtube
    case instagram
    case other
}

enum SocialPlatformDetector {
    static func platform(for url: URL) -> SocialPlatform {
        let host = url.host?.lowercased() ?? ""
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            return .tiktok
        }
        if host == "youtu.be" || host.hasSuffix(".youtu.be")
            || host == "youtube.com" || host.hasSuffix(".youtube.com") {
            return .youtube
        }
        if host == "instagram.com" || host == "instagr.am"
            || host.hasSuffix(".instagram.com") || host.hasSuffix(".instagr.am") {
            return .instagram
        }
        return .other
    }

    static func displayName(for platform: SocialPlatform) -> String {
        switch platform {
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .other: return "Web"
        }
    }

    static func systemImage(for platform: SocialPlatform) -> String {
        switch platform {
        case .tiktok: return "play.rectangle.fill"
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .other: return "link"
        }
    }
}

/// Parses strings from Share Extension / deep links into importable HTTP(S) URLs.
enum ImportLinkParser {
    static func importableURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
