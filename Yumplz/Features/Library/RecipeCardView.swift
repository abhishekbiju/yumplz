import SwiftUI

/// A compact recipe card used inside `RecipeGridView`. Displays hero image (or
/// a colour-swatch placeholder), title, time badge, cuisine tag, dietary tags
/// and a favourite heart icon.
struct RecipeCardView: View {
    let recipe: Recipe

    private var isImporting: Bool { recipe.isImportInProgress || recipe.importFailed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroSection

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(RecipeDisplayFormatter.cardTitle(recipe.title))
                        .font(.mkHeading)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if !isImporting {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(recipe.isFavorite ? Color.red : Color.secondary)
                            .font(.system(size: 15, weight: .medium))
                    }
                }

                if isImporting {
                    importStatusRow
                } else {
                    metadataRow
                }
            }
            .padding(12)
        }
        .glassCard(cornerRadius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isImporting ? 0.92 : 1)
    }

    private var importStatusRow: some View {
        HStack(spacing: 8) {
            if recipe.importFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(recipe.importStatusLabel)
                    .font(.mkCaption)
                    .foregroundStyle(recipe.importFailed ? .orange : .secondary)
                    .lineLimit(2)
                // On-device AI parsing has no incremental progress to report,
                // and can run several minutes — a static label with no ticking
                // clock is indistinguishable from a hang. A live elapsed timer
                // is the cheapest honest signal that it's still working.
                if !recipe.importFailed, let importedAt = recipe.importedAt {
                    TimelineView(.periodic(from: importedAt, by: 1)) { context in
                        Text(Self.elapsedLabel(from: importedAt, to: context.date))
                            .font(.mkCaption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private static func elapsedLabel(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0 ? "\(minutes)m \(remainder)s" : "\(remainder)s"
    }

    private var metadataRow: some View {
        Group {
            HStack(spacing: 6) {
                if let totalTime = recipe.totalTimeSeconds {
                    Label(formatTime(totalTime), systemImage: "clock")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                }
                if let cuisine = recipe.cuisine {
                    TagChip(text: cuisine)
                }
            }

            if !recipe.dietaryTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(recipe.dietaryTags.prefix(2), id: \.self) { tag in
                        TagChip(text: tag, color: .mkGreen)
                    }
                }
            }
        }
    }

    // MARK: - Hero image / placeholder

    @ViewBuilder
    private var heroSection: some View {
        if let data = recipe.heroImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .clipped()
        } else {
            ZStack {
                placeholderGradient
                if recipe.isImportInProgress {
                    ProgressView()
                        .tint(.white)
                } else if recipe.importFailed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 26, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(height: 120)
        }
    }

    private var placeholderGradient: LinearGradient {
        let palettes: [(Color, Color)] = [
            (.accentColor.opacity(0.65), .mkLilac.opacity(0.35)),
            (.mkGreen.opacity(0.60), .teal.opacity(0.30)),
            (.mkLilac.opacity(0.70), .accentColor.opacity(0.40)),
            (.purple.opacity(0.50), .pink.opacity(0.30)),
            (.teal.opacity(0.55), .blue.opacity(0.30)),
        ]
        let idx = abs(recipe.title.hashValue) % palettes.count
        return LinearGradient(
            colors: [palettes[idx].0, palettes[idx].1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
    }
}

#Preview {
    let recipe = Recipe(title: "Sourdough Focaccia")
    recipe.cookTimeSeconds = 25 * 60
    recipe.cuisine = "Italian"
    recipe.dietaryTags = ["Vegan", "Dairy-free"]
    recipe.isFavorite = true

    let unfav = Recipe(title: "Quick Scrambled Eggs")
    unfav.prepTimeSeconds = 5 * 60
    unfav.cookTimeSeconds = 3 * 60

    return ZStack {
        WarmGlassBackground()
        HStack(spacing: 12) {
            RecipeCardView(recipe: recipe)
            RecipeCardView(recipe: unfav)
        }
        .padding()
    }
}
