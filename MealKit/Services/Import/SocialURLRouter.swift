import Foundation

// MARK: - Public types

enum SocialPlatform: Equatable, Sendable {
    case tiktok
    case youtube
    case instagram
    case other
}

enum SocialURLResult: Sendable {
    case text(String)      // Extracted text ready for LLM
    case needsVideoFile    // Instagram / unsupported — prompt user to share the file
    case useHTMLScrape     // Non-social URL — fall back to existing HTML scraper
}

// MARK: - Router

/// Stateless URL router that inspects a URL, identifies the platform, and
/// performs the best available text-extraction strategy. Implemented as a
/// caseless enum so callers cannot instantiate it.
enum SocialURLRouter: Sendable {

    // MARK: – Platform detection

    /// Returns the social platform for the given URL based on its host.
    static func platform(for url: URL) -> SocialPlatform {
        let host = url.host?.lowercased() ?? ""
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            return .tiktok
        } else if host == "youtu.be"
                    || host == "youtube.com"
                    || host.hasSuffix(".youtube.com") {
            return .youtube
        } else if host == "instagram.com"
                    || host == "instagr.am"
                    || host.hasSuffix(".instagram.com")
                    || host.hasSuffix(".instagr.am") {
            return .instagram
        } else {
            return .other
        }
    }

    // MARK: – Main entry point

    /// Dispatches to the appropriate extraction strategy.
    /// Must be called from a `@MainActor` context because `WhisperTranscriptionService`
    /// is `@MainActor`-isolated.
    @MainActor
    static func route(url: URL, whisper: WhisperTranscriptionService) async throws -> SocialURLResult {
        switch platform(for: url) {
        case .instagram:
            return .needsVideoFile
        case .other:
            return .useHTMLScrape
        case .tiktok:
            return try await routeTikTok(url: url, whisper: whisper)
        case .youtube:
            return try await routeYouTube(url: url)
        }
    }

    // MARK: – YouTube

    /// Extracts the video ID from a full `youtube.com/watch?v=` or short `youtu.be/` URL.
    static func extractYouTubeVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let parts = url.pathComponents
            guard parts.count >= 2 else { return nil }
            let id = parts[1]
            return id.isEmpty ? nil : id
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            return comps.queryItems?.first(where: { $0.name == "v" })?.value
        }
        return nil
    }

    /// Joins all `utf8` segments from a YouTube `timedtext?fmt=json3` response.
    static func parseTimedtextJSON(_ data: Data) -> String {
        guard
            let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let events = json["events"] as? [[String: Any]]
        else { return "" }

        var parts: [String] = []
        for event in events {
            guard let segs = event["segs"] as? [[String: Any]] else { continue }
            for seg in segs {
                if let text = seg["utf8"] as? String {
                    parts.append(text)
                }
            }
        }

        // Join raw parts (may contain embedded newlines from the API), then
        // normalise whitespace so the LLM receives clean text.
        return parts.joined()
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor
    private static func routeYouTube(url: URL) async throws -> SocialURLResult {
        guard let videoID = extractYouTubeVideoID(from: url) else {
            return .useHTMLScrape
        }

        // Try captions via the timedtext API first (no auth required for public videos).
        let timedtextURLStr = "https://www.youtube.com/api/timedtext?v=\(videoID)&lang=en&fmt=json3"
        if let timedtextURL = URL(string: timedtextURLStr),
           let (data, _) = try? await URLSession.shared.data(from: timedtextURL) {
            let transcript = parseTimedtextJSON(data)
            if !transcript.isEmpty {
                return .text(transcript)
            }
        }

        // Fall back to og:description / meta description from the page.
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let html = String(data: data, encoding: .utf8),
           let desc = extractMetaDescription(from: html), !desc.isEmpty {
            return .text(desc)
        }

        return .useHTMLScrape
    }

    private static func extractMetaDescription(from html: String) -> String? {
        // Pattern A: name/property attribute appears before content attribute.
        let patA = #"<meta[^>]+(?:name|property)="(?:description|og:description)"[^>]+content="([^"]+)""#
        if let m = try? NSRegularExpression(pattern: patA, options: .caseInsensitive),
           let match = m.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        // Pattern B: content attribute appears before name/property attribute.
        let patB = #"<meta[^>]+content="([^"]+)"[^>]+(?:name|property)="(?:description|og:description)""#
        if let m = try? NSRegularExpression(pattern: patB, options: .caseInsensitive),
           let match = m.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }

    // MARK: – TikTok

    /// Parses the `__UNIVERSAL_DATA_FOR_REHYDRATION__` script from a TikTok HTML page.
    /// Returns the caption (`desc`), an audio CDN URL (music.playUrl or video.downloadAddr),
    /// and the author's bio link URL — any of which may be `nil` if absent or malformed.
    static func parseTikTokRehydrationHTML(_ html: String) -> (desc: String?, audioURL: URL?, bioLink: URL?) {
        let pattern = #"<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>([\s\S]*?)<\/script>"#
        guard
            let regex  = try? NSRegularExpression(pattern: pattern),
            let match  = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range  = Range(match.range(at: 1), in: html)
        else { return (nil, nil, nil) }

        let jsonString = String(html[range])
        guard
            let data       = jsonString.data(using: .utf8),
            let root       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scope      = root["DEFAULT_SCOPE"] as? [String: Any],
            let detail     = scope["webapp.video-detail"] as? [String: Any],
            let itemInfo   = detail["itemInfo"] as? [String: Any],
            let itemStruct = itemInfo["itemStruct"] as? [String: Any]
        else { return (nil, nil, nil) }

        let desc = itemStruct["desc"] as? String

        let audioURL: URL? = {
            if let music   = itemStruct["music"] as? [String: Any],
               let playURL = music["playUrl"] as? String,
               let url     = URL(string: playURL) { return url }
            if let video   = itemStruct["video"] as? [String: Any],
               let addr    = video["downloadAddr"] as? String,
               let url     = URL(string: addr) { return url }
            return nil
        }()

        let bioLink: URL? = {
            if let author  = itemStruct["author"] as? [String: Any],
               let bio     = author["bioLink"] as? [String: Any],
               let link    = bio["link"] as? String,
               let url     = URL(string: link) { return url }
            return nil
        }()

        return (desc, audioURL, bioLink)
    }

    @MainActor
    private static func routeTikTok(url: URL, whisper: WhisperTranscriptionService) async throws -> SocialURLResult {

        // ── Tier 1 · Caption from rehydration JSON ──────────────────────────────
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")

        let html: String
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            html = str
        } else {
            html = ""
        }

        let (desc, audioURL, bioLink) = parseTikTokRehydrationHTML(html)

        let wordCount: (String?) -> Int = {
            ($0 ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }

        if let desc, wordCount(desc) >= 50 {
            return .text(desc)
        }

        // ── Tier 2 · Audio CDN download + WhisperKit transcription ──────────────
        if let audioURL {
            do {
                try await whisper.ensureReady()
                let tempFile = try await downloadToTemp(url: audioURL, ext: "m4a")
                defer { try? FileManager.default.removeItem(at: tempFile) }

                let transcript = try await whisper.transcribe(audioURL: tempFile)
                if wordCount(transcript) >= 20 {
                    return .text(transcript)
                }
            } catch {
                // Tier 2 failed — fall through to Tier 3.
            }
        }

        // ── Tier 3 · Bio-link or in-caption URL scrape ──────────────────────────
        let bioLinkURL: URL? = bioLink ?? extractURLFromText(desc ?? "")
        if let bioLinkURL {
            var bioReq = URLRequest(url: bioLinkURL, timeoutInterval: 20)
            bioReq.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: bioReq),
               let bioHTML = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let scraped = stripHTML(bioHTML)
                if !scraped.isEmpty { return .text(scraped) }
            }
        }

        // Return thin caption if we have anything rather than failing silently.
        if let desc, !desc.isEmpty { return .text(desc) }

        return .useHTMLScrape
    }

    // MARK: – Shared helpers

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Mobile/15E148 Safari/604.1"

    private static func downloadToTemp(url: URL, ext: String) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: dest)
        return dest
    }

    private static func extractURLFromText(_ text: String) -> URL? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return nil }
        return detector
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { $0.url }
            .first
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>",
                                  with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",
                                  with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
