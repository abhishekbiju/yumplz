import Foundation

/// Post-processes LLM output against the original source to drop hallucinations
/// and social noise that survived parsing.
enum RecipeImportSanitizer {

    static func sanitize(_ dto: ParsedRecipeDTO, context: RecipeImportContext) -> ParsedRecipeDTO {
        var copy = dto
        copy.title = resolvedTitle(from: dto.title, context: context)
        copy.summary = dto.summary.map { SocialRecipeTextCleaner.cleanInstruction($0) }
        copy.ingredients = filterIngredients(dto.ingredients, source: context.cleanedText)
        copy.steps = dto.steps.compactMap { step in
            let text = SocialRecipeTextCleaner.cleanInstruction(step.text)
            guard !text.isEmpty, !step.isSectionHeader || text.count >= 4 else { return nil }
            return ParsedRecipeDTO.ParsedStepDTO(
                text: text,
                timerSeconds: step.timerSeconds,
                isSectionHeader: step.isSectionHeader
            )
        }
        copy.tags = cleanTags(dto.tags)
        copy.dietaryTags = cleanTags(dto.dietaryTags)
        copy.cuisine = dto.cuisine.map { SocialRecipeTextCleaner.stripSocialNoise(from: $0) }
        return RecipeImportEnricher.enrich(copy, context: context)
    }

    private static func resolvedTitle(from llmTitle: String, context: RecipeImportContext) -> String {
        let cleanedLLM = RecipeDisplayFormatter.cleanTitle(llmTitle)
        guard let videoTitle = context.videoTitle else {
            return cleanedLLM.isEmpty ? "Imported Recipe" : cleanedLLM
        }

        let cleanedVideo = RecipeDisplayFormatter.cleanTitle(videoTitle)
        if titlesMatch(cleanedLLM, cleanedVideo) { return cleanedVideo }
        if titleAppearsInSource(cleanedLLM, source: context.cleanedText) { return cleanedLLM }
        return cleanedVideo.isEmpty ? cleanedLLM : cleanedVideo
    }

    private static func titlesMatch(_ a: String, _ b: String) -> Bool {
        let al = a.lowercased(), bl = b.lowercased()
        return al.contains(bl) || bl.contains(al)
    }

    private static func titleAppearsInSource(_ title: String, source: String) -> Bool {
        source.lowercased().contains(title.lowercased())
    }

    private static func filterIngredients(
        _ ingredients: [ParsedRecipeDTO.ParsedIngredientDTO],
        source: String
    ) -> [ParsedRecipeDTO.ParsedIngredientDTO] {
        let sourceLower = source.lowercased()
        return ingredients.filter { ing in
            ingredientSupportedBySource(ing, sourceLower: sourceLower)
        }
    }

    static func ingredientSupportedBySource(
        _ ing: ParsedRecipeDTO.ParsedIngredientDTO,
        sourceLower: String
    ) -> Bool {
        let candidates = [ing.name, ing.originalText]
            .flatMap { $0.lowercased().split(whereSeparator: { !$0.isLetter }) }
            .map(String.init)
            .filter { $0.count >= 3 }

        guard !candidates.isEmpty else { return true }

        // Require at least one substantive token from the ingredient to appear in source.
        return candidates.contains { token in sourceLower.contains(token) }
    }

    private static func cleanTags(_ tags: [String]) -> [String] {
        tags
            .map { SocialRecipeTextCleaner.stripSocialNoise(from: $0) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}
