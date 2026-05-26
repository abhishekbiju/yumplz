import SwiftUI

/// 600 × 800 pt canvas rendered via `ImageRenderer` for the share sheet image payload.
///
/// Layout:
///   Top 60 %  — hero image or warm gradient with fork.knife SF symbol
///   Bottom 40 % — glassmorphic card: title, cuisine chip, cook time, servings
///   Footer     — "MealKit" small secondary label
///
/// Intentionally free of `@Environment` dependencies so it renders correctly
/// inside `ImageRenderer` without a live `ModelContext`.
struct RecipeShareCardView: View {

    let recipe: Recipe

    private let canvasWidth: CGFloat  = 600
    private let canvasHeight: CGFloat = 800
    private var heroHeight: CGFloat   { canvasHeight * 0.60 }
    private var cardHeight: CGFloat   { canvasHeight * 0.40 }

    var body: some View {
        ZStack(alignment: .bottom) {
            heroLayer
            infoCard
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroLayer: some View {
        if let data = recipe.heroImageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvasWidth, height: canvasHeight)
                .clipped()
        } else {
            LinearGradient(
                colors: [.mkBackground, .mkSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: canvasWidth, height: canvasHeight)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: 100, weight: .ultraLight))
                    .foregroundStyle(Color.accentColor.opacity(0.50))
            )
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content
            VStack(alignment: .leading, spacing: 10) {
                Text(recipe.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let cuisine = recipe.cuisine {
                        TagChip(text: cuisine)
                    }
                    if let total = recipe.totalTimeSeconds, total > 0 {
                        Label(formatTime(total), systemImage: "clock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Label(
                        "\(recipe.servings) serving\(recipe.servings == 1 ? "" : "s")",
                        systemImage: "person.2"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            // Footer
            Text("MealKit")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: canvasWidth, height: cardHeight)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

// MARK: - Preview

#Preview {
    let r = Recipe(title: "Sourdough Focaccia")
    r.servings = 8
    r.cookTimeSeconds = 25 * 60
    r.cuisine = "Italian"
    return RecipeShareCardView(recipe: r)
        .frame(width: 300, height: 400)
        .scaleEffect(0.5)
}
