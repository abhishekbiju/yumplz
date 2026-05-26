import Foundation

// MARK: - Parsed recipe DTO

/// The raw JSON structure returned by the LLM during Import.
/// Validated and mapped into SwiftData models by `ImportService`.
struct ParsedRecipeDTO: Codable, Sendable {
    var title: String
    var summary: String?
    var servings: Int
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var ingredients: [ParsedIngredientDTO]
    var steps: [ParsedStepDTO]
    var nutrition: ParsedNutritionDTO?
    var tags: [String]
    var cuisine: String?
    var dietaryTags: [String]

    struct ParsedIngredientDTO: Codable, Sendable {
        var originalText: String
        var quantity: Double?
        var unit: String?
        var name: String
        var prep: String?
        var storeCategory: String
    }

    struct ParsedStepDTO: Codable, Sendable {
        var text: String
        var timerSeconds: Int?
        var isSectionHeader: Bool
    }

    struct ParsedNutritionDTO: Codable, Sendable {
        var calories: Int?
        var proteinGrams: Double?
        var carbsGrams: Double?
        var fatGrams: Double?
    }
}

// MARK: - Prompt templates

/// Static factory methods for building LLM prompts.
/// Each prompt is designed for Llama 3.2 3B Instruct with a tight JSON schema
/// so the model produces structured output reliably without grammar constraints.
enum RecipePrompts {

    // MARK: Recipe extraction

    static let systemPrompt = """
    You are a precise recipe data extractor. Extract recipe information from \
    the provided text and return ONLY valid JSON matching the exact schema \
    provided. Do not add commentary, markdown, or any text outside the JSON \
    object. If a field cannot be determined, use null. Never invent data.
    """

    /// Full recipe extraction. `text` is the cleaned body of a recipe page,
    /// OCR output, transcription, or pasted text.
    static func recipeExtractionPrompt(from text: String) -> String {
        let truncated = String(text.prefix(6000))  // stay within 3B context budget
        return """
        Extract all recipe information from the text below. Return a single \
        JSON object matching this schema exactly:

        {
          "title": "string",
          "summary": "string or null",
          "servings": integer,
          "prepTimeMinutes": integer or null,
          "cookTimeMinutes": integer or null,
          "ingredients": [
            {
              "originalText": "verbatim ingredient line from source",
              "quantity": number or null,
              "unit": "string or null (e.g. cup, tbsp, g, oz, clove)",
              "name": "core food item only, no prep",
              "prep": "preparation method or null (e.g. diced, sifted)",
              "storeCategory": "one of: Produce, Dairy & Eggs, Meat & Seafood, \
        Pantry, Bakery, Frozen, Beverages, Spices & Baking, Other"
            }
          ],
          "steps": [
            {
              "text": "full instruction text",
              "timerSeconds": integer or null (convert any duration to seconds),
              "isSectionHeader": boolean (true only for section dividers like \
        'For the dough' with no actionable instruction)
            }
          ],
          "nutrition": {
            "calories": integer or null,
            "proteinGrams": number or null,
            "carbsGrams": number or null,
            "fatGrams": number or null
          },
          "tags": ["array", "of", "strings"],
          "cuisine": "string or null",
          "dietaryTags": ["e.g. vegetarian, vegan, gluten-free, dairy-free"]
        }

        SOURCE TEXT:
        \(truncated)

        JSON:
        """
    }

    // MARK: Plan generation (decomposed)

    /// Step 1 — enumerate (date, slot) pairs for a date range.
    static func planSlotListPrompt(startDate: Date, days: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateString = formatter.string(from: startDate)

        return """
        List all meal slots for a \(days)-day meal plan starting \(dateString). \
        Slots per day: Breakfast, Lunch, Dinner, Snack. \
        Return ONLY a JSON array of objects: \
        [{"date":"YYYY-MM-DD","slot":"Breakfast"},...]

        JSON:
        """
    }

    /// Step 2 — given a slot's constraints, pick the best recipe from candidates.
    /// `candidates` is a compact JSON array of `{id, title, cuisine, dietaryTags, \
    /// prepTimeMinutes, cookTimeMinutes}`.
    static func planCandidatePickPrompt(
        date: String,
        slot: String,
        constraints: String,
        candidatesJSON: String
    ) -> String {
        return """
        You are selecting a recipe for a meal plan. Pick exactly ONE recipe \
        from the candidates that best fits the constraints. \
        Return ONLY {"selectedId":"<id>","reason":"<one sentence>"}.

        Slot: \(slot) on \(date)
        Constraints: \(constraints)
        Candidates:
        \(String(candidatesJSON.prefix(3000)))

        JSON:
        """
    }

    /// Step 3 — review the full draft plan for variety and flag problematic pairs.
    static func planVarietyCheckPrompt(draftPlanJSON: String) -> String {
        return """
        Review this meal plan draft for obvious variety issues: same protein \
        two days in a row, same cuisine three days in a row, or \
        nutritionally unbalanced days. \
        Return ONLY a JSON array of swap suggestions (may be empty): \
        [{"date":"YYYY-MM-DD","slot":"Dinner","issue":"same protein as yesterday",\
        "suggestedSwapTitle":"something different"}]

        Draft plan:
        \(String(draftPlanJSON.prefix(4000)))

        JSON:
        """
    }
}

// MARK: - JSON extraction helpers

extension String {
    /// Extracts the first JSON object or array from a raw LLM response.
    /// Models occasionally emit preamble text before the JSON — this trims it.
    func extractedJSON() -> String? {
        // Find first '{' or '['
        let delimiters: [Character] = ["{", "["]
        guard let start = firstIndex(where: { delimiters.contains($0) }) else {
            return nil
        }
        // Find the matching close bracket by scanning from the end
        let openChar: Character = self[start]
        let closeChar: Character = openChar == "{" ? "}" : "]"
        guard let end = lastIndex(of: closeChar) else { return nil }
        guard end >= start else { return nil }
        return String(self[start...end])
    }
}
