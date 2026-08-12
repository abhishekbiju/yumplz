import Foundation

/// Maps an `Ingredient` or `GroceryItem` to a decorative emoji.
///
/// Resolution order for `Ingredient`:
///  1. Keyword match on `parsedName` (lowercased, `contains`)
///  2. Keyword match on `originalText` (lowercased) as fallback
///  3. Store-category fallback emoji
///
/// Keyword table is sorted by keyword length (longest first) so that
/// "bell pepper" matches before "pepper", "peanut butter" before "peanut", etc.
enum IngredientEmojiMapper {

    // MARK: - Public API

    static func emoji(for ingredient: Ingredient) -> String {
        if let name = ingredient.parsedName, !name.isEmpty,
           let found = findEmoji(in: name.lowercased()) {
            return found
        }
        let text = ingredient.originalText.lowercased()
        if !text.isEmpty, let found = findEmoji(in: text) {
            return found
        }
        return categoryEmoji(for: ingredient.storeCategory ?? .other)
    }

    static func emoji(for item: GroceryItem) -> String {
        let name = item.name.lowercased()
        if !name.isEmpty, let found = findEmoji(in: name) {
            return found
        }
        return categoryEmoji(for: item.storeCategory)
    }

    // MARK: - Category Fallback

    static func categoryEmoji(for category: StoreCategory) -> String {
        switch category {
        case .produce:      return "🥬"
        case .dairyEggs:    return "🥛"
        case .meatSeafood:  return "🍖"
        case .bakery:       return "🍞"
        case .pantry:       return "🫙"
        case .frozen:       return "🧊"
        case .beverages:    return "🥤"
        case .spicesBaking: return "🧂"
        case .other:        return "🍽️"
        }
    }

    // MARK: - Private

    private static func findEmoji(in text: String) -> String? {
        for (keyword, emoji) in sortedKeywordTable where text.contains(keyword) {
            return emoji
        }
        return nil
    }

    /// Keyword table sorted once by keyword length (longest first) for greedy matching.
    private static let sortedKeywordTable: [(String, String)] = {
        rawKeywordTable.sorted { $0.0.count > $1.0.count }
    }()

    // swiftlint:disable line_length
    private static let rawKeywordTable: [(String, String)] = [

        // ── Produce ──────────────────────────────────────────────────────────
        ("sweet potato", "🍠"),
        ("bell pepper", "🫑"),
        ("scallion", "🧅"),
        ("zucchini", "🥒"),
        ("eggplant", "🍆"),
        ("asparagus", "🥦"),
        ("artichoke", "🫚"),
        ("pumpkin", "🎃"),
        ("broccoli", "🥦"),
        ("spinach", "🥬"),
        ("lettuce", "🥬"),
        ("avocado", "🥑"),
        ("mushroom", "🍄"),
        ("cucumber", "🥒"),
        ("cilantro", "🌿"),
        ("rosemary", "🌿"),
        ("parsley", "🌿"),
        ("celery", "🥬"),
        ("tomato", "🍅"),
        ("carrot", "🥕"),
        ("garlic", "🧄"),
        ("ginger", "🫚"),
        ("pepper", "🫑"),
        ("shallot", "🧅"),
        ("chili", "🌶️"),
        ("lemon", "🍋"),
        ("potato", "🥔"),
        ("onion", "🧅"),
        ("mango", "🥭"),
        ("strawberry", "🍓"),
        ("blueberry", "🫐"),
        ("raspberry", "🍓"),
        ("watermelon", "🍉"),
        ("pineapple", "🍍"),
        ("pomegranate", "🍎"),
        ("cherry", "🍒"),
        ("coconut", "🥥"),
        ("orange", "🍊"),
        ("banana", "🍌"),
        ("apple", "🍎"),
        ("grape", "🍇"),
        ("peach", "🍑"),
        ("lime", "🍋"),
        ("pear", "🍐"),
        ("kale", "🥬"),
        ("lentil", "🫘"),
        ("chickpea", "🫘"),
        ("bean", "🫘"),
        ("beet", "🫚"),
        ("radish", "🫚"),
        ("fig", "🍑"),
        ("date", "🍑"),
        ("herbs", "🌿"),
        ("basil", "🌿"),
        ("mint", "🌿"),
        ("thyme", "🌿"),
        ("oregano", "🌿"),
        ("dill", "🌿"),
        ("chive", "🌿"),
        ("leek", "🧅"),
        ("corn", "🌽"),
        ("pea", "🫛"),

        // ── Meat & Seafood ────────────────────────────────────────────────────
        ("chicken", "🍗"),
        ("turkey", "🍗"),
        ("salmon", "🐟"),
        ("anchovy", "🐟"),
        ("sardine", "🐟"),
        ("lobster", "🦞"),
        ("sausage", "🌭"),
        ("shrimp", "🦐"),
        ("prawn", "🦐"),
        ("scallop", "🫧"),
        ("mussel", "🐚"),
        ("steak", "🥩"),
        ("bacon", "🥓"),
        ("lamb", "🥩"),
        ("duck", "🍗"),
        ("beef", "🥩"),
        ("pork", "🥓"),
        ("tuna", "🐟"),
        ("crab", "🦀"),
        ("clam", "🐚"),
        ("fish", "🐟"),
        ("cod", "🐟"),

        // ── Dairy & Eggs ──────────────────────────────────────────────────────
        ("half and half", "🥛"),
        ("cream cheese", "🧀"),
        ("heavy cream", "🥛"),
        ("sour cream", "🥛"),
        ("mozzarella", "🧀"),
        ("parmesan", "🧀"),
        ("cheddar", "🧀"),
        ("ricotta", "🧀"),
        ("yogurt", "🫙"),
        ("butter", "🧈"),
        ("cheese", "🧀"),
        ("cream", "🥛"),
        ("milk", "🥛"),
        ("feta", "🧀"),
        ("egg", "🥚"),

        // ── Bakery / Grains ───────────────────────────────────────────────────
        ("baguette", "🥖"),
        ("tortilla", "🫓"),
        ("noodle", "🍜"),
        ("semolina", "🌾"),
        ("couscous", "🌾"),
        ("quinoa", "🌾"),
        ("cornstarch", "🫙"),
        ("cornmeal", "🌽"),
        ("cracker", "🫙"),
        ("cereal", "🥣"),
        ("barley", "🌾"),
        ("pasta", "🍝"),
        ("bread", "🍞"),
        ("flour", "🌾"),
        ("pita", "🫓"),
        ("rice", "🍚"),
        ("roll", "🍞"),
        ("oat", "🌾"),

        // ── Pantry / Sauces ───────────────────────────────────────────────────
        ("peanut butter", "🥜"),
        ("almond butter", "🥜"),
        ("coconut milk", "🥥"),
        ("almond milk", "🥛"),
        ("tomato sauce", "🍅"),
        ("lemon juice", "🍋"),
        ("lime juice", "🍋"),
        ("soy sauce", "🫙"),
        ("olive oil", "🫒"),
        ("vanilla", "🫙"),
        ("chocolate", "🍫"),
        ("vinegar", "🫙"),
        ("tahini", "🫙"),
        ("broth", "🍲"),
        ("stock", "🍲"),
        ("honey", "🍯"),
        ("sugar", "🫙"),
        ("syrup", "🍯"),
        ("water", "💧"),
        ("cocoa", "🍫"),
        ("coffee", "☕"),
        ("vodka", "🍸"),
        ("wine", "🍷"),
        ("beer", "🍺"),
        ("miso", "🫙"),
        ("salt", "🧂"),
        ("jam", "🍯"),
        ("rum", "🍹"),
        ("tea", "🍵"),
        ("oil", "🫙"),

        // ── Spices & Baking ───────────────────────────────────────────────────
        ("baking powder", "🫙"),
        ("baking soda", "🫙"),
        ("black pepper", "🫚"),
        ("cinnamon", "🫚"),
        ("cardamom", "🫚"),
        ("turmeric", "🫚"),
        ("coriander", "🫚"),
        ("cayenne", "🌶️"),
        ("mustard", "🫚"),
        ("paprika", "🫚"),
        ("fennel", "🫚"),
        ("nutmeg", "🫚"),
        ("clove", "🫚"),
        ("cumin", "🫚"),
        ("curry", "🫚"),
        ("yeast", "🫙"),
        ("bay leaf", "🌿"),

        // ── Nuts & Seeds ──────────────────────────────────────────────────────
        ("sunflower seed", "🌻"),
        ("pumpkin seed", "🎃"),
        ("pistachio", "🥜"),
        ("flaxseed", "🌰"),
        ("pine nut", "🌰"),
        ("almond", "🥜"),
        ("walnut", "🥜"),
        ("cashew", "🥜"),
        ("sesame", "🌰"),
        ("peanut", "🥜"),
        ("pecan", "🥜"),
        ("chia", "🌰"),
    ]
    // swiftlint:enable line_length
}
