import Foundation

/// Pure, framework-free functions that generate share payloads from a Recipe.
/// Stateless enum so every function is easily unit-tested without a SwiftData
/// container or a running app.
enum RecipeShareFormatter {

    // MARK: - Plain text

    /// Formats a recipe as human-readable plain text suitable for Messages, Mail,
    /// and the deep-link payload.
    ///
    /// ```
    /// [Title]
    /// Serves [N] · [X] min
    ///
    /// INGREDIENTS
    /// • [originalText]
    ///
    /// STEPS
    /// 1. [step text]
    ///
    /// Shared from yumplz
    /// ```
    static func plainText(for recipe: Recipe) -> String {
        var lines: [String] = []

        // Title
        lines.append(recipe.title)

        // Subtitle: servings + total time
        var subtitleParts: [String] = ["Serves \(recipe.servings)"]
        if let total = recipe.totalTimeSeconds, total > 0 {
            subtitleParts.append(formatTime(total))
        }
        lines.append(subtitleParts.joined(separator: " · "))
        lines.append("")

        // Ingredients
        let ingredients = (recipe.ingredients ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
        if !ingredients.isEmpty {
            lines.append("INGREDIENTS")
            for ingredient in ingredients {
                lines.append("• \(ingredient.originalText)")
            }
            lines.append("")
        }

        // Steps
        let steps = (recipe.steps ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
        if !steps.isEmpty {
            lines.append("STEPS")
            var stepNumber = 1
            for step in steps {
                if step.isSectionHeader {
                    lines.append(step.text)
                } else {
                    lines.append("\(stepNumber). \(step.text)")
                    stepNumber += 1
                }
            }
            lines.append("")
        }

        lines.append("Shared from yumplz")

        return lines.joined(separator: "\n")
    }

    // MARK: - Deep link

    /// Builds a `yumplz://import?text=<percent-encoded plain text>` URL.
    /// Returns `nil` only if percent-encoding somehow fails (practically impossible).
    static func deepLinkURL(for plainText: String) -> URL? {
        var components = URLComponents()
        components.scheme = "yumplz"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "text", value: plainText)]
        return components.url
    }

    // MARK: - Private helpers

    private static func formatTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 3600 {
            return "\(seconds / 60) min"
        }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
