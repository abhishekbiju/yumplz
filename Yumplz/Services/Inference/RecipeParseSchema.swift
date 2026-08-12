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

    init(
        title: String,
        summary: String? = nil,
        servings: Int = 4,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        ingredients: [ParsedIngredientDTO] = [],
        steps: [ParsedStepDTO] = [],
        nutrition: ParsedNutritionDTO? = nil,
        tags: [String] = [],
        cuisine: String? = nil,
        dietaryTags: [String] = []
    ) {
        self.title = title
        self.summary = summary
        self.servings = max(1, servings)
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.ingredients = ingredients
        self.steps = steps
        self.nutrition = nutrition
        self.tags = tags
        self.cuisine = cuisine
        self.dietaryTags = dietaryTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Imported Recipe"
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        servings = max(1, try container.decodeIfPresent(Int.self, forKey: .servings) ?? 4)
        prepTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .prepTimeMinutes)
        cookTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .cookTimeMinutes)
        ingredients = try container.decodeIfPresent([ParsedIngredientDTO].self, forKey: .ingredients) ?? []
        steps = try container.decodeIfPresent([ParsedStepDTO].self, forKey: .steps) ?? []
        nutrition = try container.decodeIfPresent(ParsedNutritionDTO.self, forKey: .nutrition)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        cuisine = try container.decodeIfPresent(String.self, forKey: .cuisine)
        dietaryTags = try container.decodeIfPresent([String].self, forKey: .dietaryTags) ?? []
    }

    struct ParsedIngredientDTO: Codable, Sendable {
        var originalText: String
        var quantity: Double?
        var unit: String?
        var name: String
        var prep: String?
        var storeCategory: String

        init(
            originalText: String,
            quantity: Double? = nil,
            unit: String? = nil,
            name: String? = nil,
            prep: String? = nil,
            storeCategory: String = "Other"
        ) {
            self.originalText = originalText
            self.quantity = quantity
            self.unit = unit
            self.name = name ?? originalText
            self.prep = prep
            self.storeCategory = storeCategory
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            originalText = try container.decodeIfPresent(String.self, forKey: .originalText)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
            unit = try container.decodeIfPresent(String.self, forKey: .unit)
            let decodedName = try container.decodeIfPresent(String.self, forKey: .name)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = (decodedName?.isEmpty == false) ? decodedName! : originalText
            prep = try container.decodeIfPresent(String.self, forKey: .prep)
            storeCategory = try container.decodeIfPresent(String.self, forKey: .storeCategory) ?? "Other"
        }
    }

    struct ParsedStepDTO: Codable, Sendable {
        var text: String
        var timerSeconds: Int?
        var isSectionHeader: Bool

        init(text: String, timerSeconds: Int? = nil, isSectionHeader: Bool = false) {
            self.text = text
            self.timerSeconds = timerSeconds
            self.isSectionHeader = isSectionHeader
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decodeIfPresent(String.self, forKey: .text)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            timerSeconds = try container.decodeIfPresent(Int.self, forKey: .timerSeconds)
            isSectionHeader = try container.decodeIfPresent(Bool.self, forKey: .isSectionHeader) ?? false
        }
    }

    struct ParsedNutritionDTO: Codable, Sendable {
        var calories: Int?
        var proteinGrams: Double?
        var carbsGrams: Double?
        var fatGrams: Double?
    }
}

// MARK: - Llama chat formatting

/// Llama 3.2 Instruct chat template shared by inference and tests.
enum LlamaChatFormatting {
    private static let beginOfText = "<|" + "begin_of_text" + "|>"
    private static let startHeader = "<|" + "start_header_id" + "|>"
    private static let endHeader = "<|" + "end_header_id" + "|>"
    private static let endOfTurn = "<|" + "eot_id" + "|>"

    static func prompt(system: String, user: String) -> String {
        beginOfText +
        startHeader + "system" + endHeader + "\n\n" + system + endOfTurn +
        startHeader + "user" + endHeader + "\n\n" + user + endOfTurn +
        startHeader + "assistant" + endHeader + "\n\n"
    }
}

// MARK: - Prompt templates

/// Static factory methods for building LLM prompts.
/// Each prompt is designed for Llama 3.2 3B Instruct with a tight JSON schema
/// so the model produces structured output reliably without grammar constraints.
enum RecipePrompts {

    // MARK: Recipe extraction

    static let systemPrompt = """
    You convert recipe text into JSON. Reply with one JSON object only. \
    No markdown, no code fences, no commentary before or after the JSON.
    """

    /// Compact extraction prompt tuned for Llama 3.2 3B — includes a concrete
    /// example so the model fills every required key.
    static func sourcePayload(videoTitle: String?, body: String) -> String {
        var parts: [String] = []
        if let videoTitle, !videoTitle.isEmpty {
            parts.append("VIDEO TITLE: \(videoTitle)")
        }
        parts.append("SOURCE TEXT:\n\(body)")
        return parts.joined(separator: "\n\n")
    }

    static func recipeExtractionPrompt(from text: String) -> String {
        let truncated = String(text.prefix(4500))
        return """
        Extract the recipe below into JSON. Use ONLY ingredients and steps from SOURCE TEXT. \
        Do not invent ingredients (no pasta unless SOURCE TEXT mentions pasta). \
        When SOURCE TEXT omits amounts, estimate realistic quantities and units for each ingredient.

        Example (follow this shape exactly):
        {"title":"Thakkali Rasam","summary":"South Indian tomato rasam","servings":4,"prepTimeMinutes":10,"cookTimeMinutes":15,"ingredients":[{"originalText":"4 ripe tomatoes","quantity":4,"unit":null,"name":"tomatoes","prep":null,"storeCategory":"Produce"},{"originalText":"1 tsp tamarind paste","quantity":1,"unit":"tsp","name":"tamarind paste","prep":null,"storeCategory":"Pantry"},{"originalText":"1/2 tsp cumin seeds","quantity":0.5,"unit":"tsp","name":"cumin seeds","prep":null,"storeCategory":"Spices & Baking"}],"steps":[{"text":"Simmer tomatoes with tamarind and spices.","timerSeconds":900,"isSectionHeader":false},{"text":"Temper mustard seeds and curry leaves; pour over rasam.","timerSeconds":null,"isSectionHeader":false}],"nutrition":null,"tags":["rasam","south indian"],"cuisine":"South Indian","dietaryTags":["Vegetarian","Gluten-Free","Dairy-Free"]}

        Rules:
        - Output ONLY the JSON object, starting with { and ending with }.
        - Always include: title, servings, ingredients, steps, tags, dietaryTags.
        - Every ingredient must have originalText with a quantity (e.g. "4 tomatoes", "1 tsp cumin").
        - Also fill quantity, unit, and name fields when you can parse them.
        - Estimate prepTimeMinutes and cookTimeMinutes when not stated; use step timerSeconds as hints.
        - Infer cuisine from the dish (e.g. rasam → South Indian).
        - Set dietaryTags from ingredients: Vegetarian/Vegan/Gluten-Free/Dairy-Free when applicable.
        - Prefer VIDEO TITLE for the dish name when it names the recipe.
        - Ignore hashtags, @mentions, URLs, and promo lines in steps.
        - Use null for unknown optional fields; use [] for empty tags/dietaryTags only if none apply.
        - storeCategory must be one of: Produce, Dairy & Eggs, Meat & Seafood, Pantry, Bakery, Frozen, Beverages, Spices & Baking, Other.
        - isSectionHeader is false unless the step is only a section heading.

        \(truncated)
        """
    }

    /// Ultra-compact fallback when the primary prompt returns unparseable JSON.
    static func compactRecipeExtractionPrompt(from text: String) -> String {
        let truncated = String(text.prefix(3500))
        return """
        Return ONE JSON object only. Use ONLY ingredients from SOURCE TEXT — do not invent items. \
        Estimate realistic quantities in originalText when SOURCE TEXT omits them.
        Keys: title, servings, prepTimeMinutes, cookTimeMinutes, ingredients, steps, tags, dietaryTags, cuisine.
        ingredients items: originalText, quantity, unit, name, storeCategory (use Other if unsure).
        steps items: text, isSectionHeader (false). Strip hashtags from step text.
        Infer cuisine, timing, and dietaryTags (Vegetarian/Vegan/Gluten-Free/Dairy-Free) when possible.
        Example: {"title":"Thakkali Rasam","servings":4,"prepTimeMinutes":10,"cookTimeMinutes":15,"ingredients":[{"originalText":"4 tomatoes","quantity":4,"name":"tomatoes","storeCategory":"Produce"}],"steps":[{"text":"Simmer tomatoes with spices.","isSectionHeader":false}],"tags":["rasam"],"cuisine":"South Indian","dietaryTags":["Vegetarian"]}

        \(truncated)
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
