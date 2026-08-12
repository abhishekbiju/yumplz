import Foundation

/// Cleaned source text plus optional video title for import / LLM parsing.
struct RecipeImportContext: Equatable, Sendable {
    var videoTitle: String?
    var cleanedText: String

    init(videoTitle: String? = nil, cleanedText: String) {
        self.videoTitle = videoTitle.map { RecipeDisplayFormatter.recipeTitle(fromVideoTitle: $0) }
        self.cleanedText = SocialRecipeTextCleaner.cleanSourceText(cleanedText)
    }

    /// Text passed to the LLM after social-noise removal.
    var llmPayload: String {
        RecipePrompts.sourcePayload(videoTitle: videoTitle, body: cleanedText)
    }
}

extension RecipeImportContext {
    static func fromRaw(body: String, videoTitle: String? = nil) -> RecipeImportContext {
        RecipeImportContext(videoTitle: videoTitle, cleanedText: body)
    }
}
