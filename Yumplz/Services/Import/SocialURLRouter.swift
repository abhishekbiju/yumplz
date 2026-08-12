import Foundation

// MARK: - Public types

enum SocialURLResult: Equatable, Sendable {
    case recipeText(RecipeImportContext)
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
        SocialPlatformDetector.platform(for: url)
    }

    // MARK: – Main entry point

    /// Dispatches to the appropriate extraction strategy.
    /// Must be called from a `@MainActor` context because `WhisperTranscriptionService`
    /// is `@MainActor`-isolated.
    @MainActor
    static func route(url: URL, session: URLSession = .shared) async throws -> SocialURLResult {
        switch platform(for: url) {
        case .instagram:
            return .needsVideoFile
        case .other:
            return .useHTMLScrape
        case .tiktok:
            return try await routeTikTok(url: url, session: session)
        case .youtube:
            return try await routeYouTube(url: url, session: session)
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
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.first == "shorts", parts.count >= 2 {
                let id = parts[1]
                return id.isEmpty ? nil : id
            }
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

    /// Pulls the public video title embedded in YouTube page JSON / meta tags.
    static func extractYouTubeVideoTitle(from html: String) -> String? {
        let patterns = [
            #""videoDetails"\s*:\s*\{[^}]*"title"\s*:\s*"((?:\\.|[^"\\])*)""#,
            #""title"\s*:\s*\{\s*"simpleText"\s*:\s*"((?:\\.|[^"\\])*)""#,
            #"<meta[^>]+property="og:title"[^>]+content="([^"]+)""#,
            #"<meta[^>]+content="([^"]+)"[^>]+property="og:title""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let decoded = decodeJSONStringEscapes(String(html[range]))
            if decoded.count >= 3 { return decoded }
        }
        return nil
    }

    /// Pulls description text embedded in YouTube page JSON (works for Shorts).
    static func extractYouTubeInlineDescription(from html: String) -> String? {
        let patterns = [
            #""shortDescription"\s*:\s*"((?:\\.|[^"\\])*)""#,
            #""attributedDescriptionBodyText"\s*:\s*\{[^}]*"content"\s*:\s*"((?:\\.|[^"\\])*)""#,
            #""description"\s*:\s*\{\s*"simpleText"\s*:\s*"((?:\\.|[^"\\])*)""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let decoded = decodeJSONStringEscapes(String(html[range]))
            if decoded.count >= 20 { return decoded }
        }
        return nil
    }

    private static func decodeJSONStringEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    @MainActor
    private static func routeYouTube(url: URL, session: URLSession) async throws -> SocialURLResult {
        guard let videoID = extractYouTubeVideoID(from: url) else {
            return .useHTMLScrape
        }

        // Fetch the watch/shorts page once — used for inline JSON + meta fallbacks.
        var pageReq = URLRequest(url: url, timeoutInterval: 20)
        pageReq.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        var pageHTML: String?
        if let (data, _) = try? await session.data(for: pageReq) {
            pageHTML = String(data: data, encoding: .utf8)
        }

        if let html = pageHTML {
            let title = extractYouTubeVideoTitle(from: html)
            if let inline = extractYouTubeInlineDescription(from: html) {
                return .recipeText(RecipeImportContext(videoTitle: title, cleanedText: inline))
            }
            if let title, title.count >= 20 {
                return .recipeText(RecipeImportContext(videoTitle: title, cleanedText: title))
            }
        }

        // Captions via timedtext (try several language codes).
        for lang in ["en", "en-US", "a.en"] {
            let timedtextURLStr = "https://www.youtube.com/api/timedtext?v=\(videoID)&lang=\(lang)&fmt=json3"
            guard let timedtextURL = URL(string: timedtextURLStr) else { continue }
            var timedtextReq = URLRequest(url: timedtextURL, timeoutInterval: 15)
            timedtextReq.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await session.data(for: timedtextReq) {
                let transcript = parseTimedtextJSON(data)
                if transcript.count >= 20 {
                    let title = pageHTML.flatMap { extractYouTubeVideoTitle(from: $0) }
                    return .recipeText(RecipeImportContext(videoTitle: title, cleanedText: transcript))
                }
            }
        }

        if let html = pageHTML,
           let desc = extractMetaDescription(from: html),
           desc.count >= 20 {
            let title = extractYouTubeVideoTitle(from: html)
            return .recipeText(RecipeImportContext(videoTitle: title, cleanedText: desc))
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
            let range  = Range(match.range(at: 1), in: html),
            let data   = String(html[range]).data(using: .utf8),
            let root   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let itemStruct = extractTikTokItemStruct(from: root)
        else { return (nil, nil, nil) }

        let desc = (itemStruct["desc"] as? String)
            ?? extractTikTokShareMetaDesc(from: root)

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

    /// TikTok embeds video JSON under several scope/detail keys depending on page type.
    static func extractTikTokItemStruct(from root: [String: Any]) -> [String: Any]? {
        let scope = (root["__DEFAULT_SCOPE__"] ?? root["DEFAULT_SCOPE"]) as? [String: Any]
        guard let scope else { return nil }

        let detailKeys = [
            "webapp.video-detail",
            "webapp.reflow.video.detail",
        ]

        for key in detailKeys {
            guard let detail = scope[key] as? [String: Any],
                  let itemInfo = detail["itemInfo"] as? [String: Any],
                  let itemStruct = itemInfo["itemStruct"] as? [String: Any] else { continue }
            return itemStruct
        }
        return nil
    }

    private static func extractTikTokShareMetaDesc(from root: [String: Any]) -> String? {
        let scope = (root["__DEFAULT_SCOPE__"] ?? root["DEFAULT_SCOPE"]) as? [String: Any]
        guard let scope else { return nil }

        for key in ["webapp.reflow.video.detail", "webapp.video-detail"] {
            guard let detail = scope[key] as? [String: Any],
                  let shareMeta = detail["shareMeta"] as? [String: Any],
                  let desc = shareMeta["desc"] as? String,
                  !desc.isEmpty else { continue }
            return desc
        }
        return nil
    }

    @MainActor
    private static func routeTikTok(url: URL, session: URLSession) async throws -> SocialURLResult {
        let canonicalURL = canonicalTikTokURL(url)

        // ── Tier 1 · Caption from rehydration JSON ──────────────────────────────
        let html = await fetchPageHTML(url: canonicalURL, session: session)
        let (desc, audioURL, bioLink) = parseTikTokRehydrationHTML(html)

        let wordCount: (String?) -> Int = {
            ($0 ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        }

        if let desc, isSubstantiveRecipeText(desc, wordCount: wordCount(desc)) {
            return .recipeText(RecipeImportContext(cleanedText: desc))
        }

        // ── Tier 2 · Audio CDN download + WhisperKit transcription ──────────────
        if let audioURL {
            do {
                let whisper = WhisperTranscriptionService()
                try await whisper.ensureReady()
                let tempFile = try await downloadToTemp(url: audioURL, ext: "m4a", session: session)
                defer { try? FileManager.default.removeItem(at: tempFile) }

                let transcript = try await whisper.transcribe(audioURL: tempFile)
                if isSubstantiveRecipeText(transcript, wordCount: wordCount(transcript)) {
                    return .recipeText(RecipeImportContext(cleanedText: transcript))
                }
            } catch {
                // Tier 2 failed — fall through.
            }
        }

        // ── Tier 3 · Bio-link or in-caption URL scrape ──────────────────────────
        let bioLinkURL: URL? = bioLink ?? extractURLFromText(desc ?? "")
        if let bioLinkURL {
            let bioHTML = await fetchPageHTML(url: bioLinkURL, session: session)
            if !bioHTML.isEmpty {
                let scraped = stripHTML(bioHTML)
                if isSubstantiveRecipeText(scraped, wordCount: wordCount(scraped)) {
                    return .recipeText(RecipeImportContext(cleanedText: scraped))
                }
            }
        }

        // ── Tier 4 · oEmbed API (reliable when HTML shell omits rehydration JSON) ─
        if let oembed = await fetchTikTokOEmbed(for: canonicalURL, session: session),
           isSubstantiveRecipeText(oembed.caption, wordCount: wordCount(oembed.caption)) {
            return .recipeText(RecipeImportContext(
                videoTitle: oembed.authorName,
                cleanedText: oembed.caption
            ))
        }

        // ── Tier 5 · Any non-empty caption from rehydration (cleaner may still pass) ─
        if let desc, !desc.isEmpty {
            let context = RecipeImportContext(cleanedText: desc)
            if context.cleanedText.count >= 40 {
                return .recipeText(context)
            }
        }

        // TikTok pages are client-rendered shells — HTML scrape yields ~22 chars.
        return .useHTMLScrape
    }

    /// Public oEmbed fetch used by tests and the TikTok routing tiers.
    static func fetchTikTokOEmbed(
        for url: URL,
        session: URLSession
    ) async -> (authorName: String?, caption: String)? {
        var components = URLComponents(string: "https://www.tiktok.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: canonicalTikTokURL(url).absoluteString)]
        guard let oembedURL = components?.url else { return nil }

        var req = URLRequest(url: oembedURL, timeoutInterval: 15)
        req.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")

        guard
            let (data, response) = try? await session.data(for: req),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let caption = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (json["author_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let caption, !caption.isEmpty else { return nil }
        return (author, caption)
    }

    private static func fetchPageHTML(url: URL, session: URLSession) async -> String {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(mobileUserAgent, forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await session.data(for: req),
            let http = response as? HTTPURLResponse,
            (200..<400).contains(http.statusCode),
            let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return "" }
        return str
    }

    /// Strips tracking query params from share URLs for a stable page fetch.
    static func canonicalTikTokURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }

    /// Matches `ImportService.validateRecipeText` — enough text for the LLM to parse.
    static func isSubstantiveRecipeText(_ text: String, wordCount: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 40 || wordCount >= 25
    }

    // MARK: – Shared helpers

    private static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Mobile/15E148 Safari/604.1"

    private static func downloadToTemp(url: URL, ext: String, session: URLSession) async throws -> URL {
        let (data, _) = try await session.data(from: url)
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
