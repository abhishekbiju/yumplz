import Foundation

/// Display-time cleanup for recipe titles shown in Library cards and detail headers.
enum RecipeDisplayFormatter {

    static func cleanTitle(_ raw: String) -> String {
        SocialRecipeTextCleaner.stripSocialNoise(from: raw)
    }

    /// Pull a human recipe name from a YouTube/social video title.
    static func recipeTitle(fromVideoTitle raw: String) -> String {
        var title = cleanTitle(raw)
        if let first = title.split(separator: "|").first {
            title = String(first)
        }
        if let first = title.split(separator: "-").first, title.split(separator: "-").count > 1 {
            // Only split on hyphen when it looks like a suffix tag, not "Tomato-Yogurt".
            let suffix = title.split(separator: "-").dropFirst().joined(separator: "-").lowercased()
            if suffix.contains("recipe") || suffix.contains("shorts") {
                title = String(title.split(separator: "-").first ?? Substring(title))
            }
        }
        title = title.replacingOccurrences(of: #"\brecipe\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        return collapse(title)
    }

    /// Short title for grid cards — strips noise and caps length.
    static func cardTitle(_ raw: String) -> String {
        let cleaned = cleanTitle(raw)
        guard cleaned.count > 52 else { return cleaned }
        return String(cleaned.prefix(49)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func collapse(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
