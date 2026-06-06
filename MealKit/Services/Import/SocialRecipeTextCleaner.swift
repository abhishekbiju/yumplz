import Foundation

/// Strips social-platform noise (hashtags, mentions, promo lines) from recipe text.
enum SocialRecipeTextCleaner {

    static func cleanSourceText(_ raw: String) -> String {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { stripSocialNoise(from: $0) }
            .filter { !$0.isEmpty && !isPromoLine($0) }

        let joined = lines.joined(separator: "\n")
        return collapseWhitespace(joined)
    }

    static func cleanInstruction(_ raw: String) -> String {
        collapseWhitespace(stripSocialNoise(from: raw))
    }

    static func stripSocialNoise(from raw: String) -> String {
        var text = raw

        // Remove URLs.
        text = text.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )

        // Remove @mentions and #hashtags.
        text = text.replacingOccurrences(
            of: #"@[\w\.]+"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"#[\p{L}\p{N}_]+"#,
            with: "",
            options: .regularExpression
        )

        return collapseWhitespace(text)
    }

    private static func isPromoLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let promoPrefixes = [
            "subscribe", "follow me", "follow us", "link in bio",
            "shop now", "download the app", "turn on notifications",
        ]
        return promoPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
