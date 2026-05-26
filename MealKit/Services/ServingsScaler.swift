import Foundation

/// Pure value type that scales ingredient quantities for a given serving count
/// and formats them for human-readable display.
///
/// Scaling is purely proportional: `scaledQty = originalQty × (displayServings / recipeServings)`.
/// The canonical `Recipe.servings` is unchanged; only the view's local `displayServings` state drives output.
struct ServingsScaler: Sendable {

    // MARK: – Public API

    /// Scales `ingredient.parsedQuantity` proportionally from `from` servings to `to` servings.
    /// Returns `nil` when `ingredient.parsedQuantity` is `nil`.
    func scaledQuantity(ingredient: Ingredient, from: Int, to: Int) -> Double? {
        guard let qty = ingredient.parsedQuantity, from > 0 else { return nil }
        return qty * Double(to) / Double(from)
    }

    /// Human-readable ingredient string for `servings`, scaled from `recipeServings`.
    ///
    /// - Returns `ingredient.originalText` unchanged when no structured parse exists.
    /// - Omits the numeric quantity for "vibe" units (pinch, dash, splash, toTaste).
    /// - Uses `ingredient.parsedCustomUnit` in place of the enum display name when present
    ///   and `ingredient.parsedUnit` is `nil`.
    func displayText(ingredient: Ingredient, servings: Int, recipeServings: Int) -> String {
        guard ingredient.hasStructuredParse else {
            return ingredient.originalText
        }

        let scaled = scaledQuantity(ingredient: ingredient, from: recipeServings, to: servings)
        let unit   = ingredient.parsedUnit
        let name   = ingredient.parsedName ?? ""

        // Vibe units omit the numeric quantity entirely.
        if let unit, unit.family == .vibe {
            let unitStr = unitDisplayName(unit: unit, qty: nil)
            return [unitStr, name].filter { !$0.isEmpty }.joined(separator: " ")
        }

        var parts: [String] = []

        if let qty = scaled {
            parts.append(formatQuantity(qty))
        }

        if let unit {
            parts.append(unitDisplayName(unit: unit, qty: scaled))
        } else if let customUnit = ingredient.parsedCustomUnit {
            parts.append(customUnit)
        }

        if !name.isEmpty {
            parts.append(name)
        }

        return parts.joined(separator: " ")
    }

    // MARK: – Private helpers

    private func formatQuantity(_ value: Double) -> String {
        // Common vulgar fractions displayed as Unicode symbols.
        let fractions: [(Double, String)] = [
            (0.25,       "¼"),
            (1.0 / 3.0,  "⅓"),
            (0.5,        "½"),
            (0.75,       "¾"),
        ]
        for (frac, symbol) in fractions where abs(value - frac) < 0.01 {
            return symbol
        }

        // Whole numbers without a decimal point.
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }

        // Everything else rounded to 1 decimal place.
        return String(format: "%.1f", value)
    }

    /// Localised display name for a `Unit`, with basic pluralisation when `qty > 1`.
    private func unitDisplayName(unit: Unit, qty: Double?) -> String {
        let plural = (qty ?? 0) > 1.0
        switch unit {
        case .tsp:     return "tsp"
        case .tbsp:    return "tbsp"
        case .cup:     return plural ? "cups"    : "cup"
        case .flOz:    return "fl oz"
        case .ml:      return "ml"
        case .l:       return "l"
        case .oz:      return "oz"
        case .lb:      return plural ? "lbs"     : "lb"
        case .g:       return "g"
        case .kg:      return "kg"
        case .piece:   return plural ? "pieces"  : "piece"
        case .clove:   return plural ? "cloves"  : "clove"
        case .slice:   return plural ? "slices"  : "slice"
        case .bunch:   return plural ? "bunches" : "bunch"
        case .can:     return plural ? "cans"    : "can"
        case .pinch:   return "pinch"
        case .dash:    return "dash"
        case .splash:  return "splash"
        case .toTaste: return "to taste"
        }
    }
}
