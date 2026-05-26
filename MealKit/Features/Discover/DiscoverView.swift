import SwiftUI
import SwiftData

// MARK: - DiscoverView

struct DiscoverView: View {
    var store: HouseRecipeStore
    var importService: ImportService

    @Environment(\.modelContext) private var context
    @State private var selectedCuisine: String? = nil
    @State private var selectedDietaryTag: String? = nil
    @State private var savedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        filterChipRow

                        if let hero = store.featured {
                            HeroCard(recipe: hero, isSaved: savedIDs.contains(hero.id)) {
                                save(hero)
                            }
                        }

                        if selectedCuisine == nil && selectedDietaryTag == nil {
                            ForEach(DiscoverSection.allCases) { section in
                                let sectionRecipes = store.recipes(forSection: section)
                                if !sectionRecipes.isEmpty {
                                    SectionRail(
                                        title: section.rawValue,
                                        recipes: sectionRecipes,
                                        savedIDs: savedIDs
                                    ) { save($0) }
                                }
                            }
                        }

                        let gridRecipes = store.filtered(
                            cuisine: selectedCuisine,
                            dietaryTag: selectedDietaryTag
                        )
                        RecipeDiscoverGrid(
                            recipes: gridRecipes,
                            savedIDs: savedIDs
                        ) { save($0) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Filter chip row

    @ViewBuilder
    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selectedCuisine == nil && selectedDietaryTag == nil) {
                    selectedCuisine = nil
                    selectedDietaryTag = nil
                }

                ForEach(store.allCuisines, id: \.self) { cuisine in
                    FilterChip(label: cuisine, isSelected: selectedCuisine == cuisine) {
                        selectedCuisine = selectedCuisine == cuisine ? nil : cuisine
                        selectedDietaryTag = nil
                    }
                }

                Divider().frame(height: 20)

                ForEach(store.allDietaryTags, id: \.self) { tag in
                    FilterChip(label: tag.localizedCapitalized, isSelected: selectedDietaryTag == tag, color: .mkGreen) {
                        selectedDietaryTag = selectedDietaryTag == tag ? nil : tag
                        selectedCuisine = nil
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Save action

    private func save(_ recipe: HouseRecipe) {
        let dto = recipe.toDTO()
        let saved = try? importService.save(dto, in: context)
        saved?.sourceKind = .contentLibrary
        try? context.save()
        savedIDs.insert(recipe.id)
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mkCaption)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? color : color.opacity(0.08))
                        .overlay(Capsule().strokeBorder(color.opacity(isSelected ? 0 : 0.25), lineWidth: 1))
                )
                .foregroundStyle(isSelected ? .white : color)
        }
        .buttonStyle(.plain)
        .animation(.mkSnap, value: isSelected)
    }
}

// MARK: - HeroCard

struct HeroCard: View {
    let recipe: HouseRecipe
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroGradient
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                HStack(spacing: 6) {
                    if let cuisine = recipe.cuisine {
                        TagChip(text: cuisine)
                            .colorScheme(.dark)
                    }
                    if let time = recipe.totalTimeMinutes {
                        Label("\(time) min", systemImage: "clock")
                            .font(.mkCaption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Text(recipe.title)
                    .font(.mkDisplay)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let summary = recipe.summary {
                    Text(summary)
                        .font(.mkCaption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }

                Button(action: onSave) {
                    Label(
                        isSaved ? "Saved ✓" : "Save to Library",
                        systemImage: isSaved ? "checkmark.circle.fill" : "bookmark"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isSaved ? Color.mkGreen : .white)
                    )
                    .foregroundStyle(isSaved ? .white : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .glassCard(cornerRadius: 20)
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
    }

    private var heroGradient: LinearGradient {
        let palettes: [(Color, Color)] = [
            (.accentColor, .mkLilac.opacity(0.7)),
            (.mkGreen, .teal),
            (.purple, .blue.opacity(0.7)),
            (.pink.opacity(0.9), .accentColor.opacity(0.7)),
            (.teal, .mkGreen.opacity(0.8)),
        ]
        let idx = abs(recipe.title.hashValue) % palettes.count
        return LinearGradient(
            colors: [palettes[idx].0.opacity(0.85), palettes[idx].1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - SectionRail

struct SectionRail: View {
    let title: String
    let recipes: [HouseRecipe]
    let savedIDs: Set<String>
    let onSave: (HouseRecipe) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.mkHeading)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recipes) { recipe in
                        HouseRecipeCard(recipe: recipe, isSaved: savedIDs.contains(recipe.id)) {
                            onSave(recipe)
                        }
                        .frame(width: 160)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - HouseRecipeCard (compact for rails)

private struct HouseRecipeCard: View {
    let recipe: HouseRecipe
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                cardGradient
                    .frame(height: 100)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16, bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0, topTrailingRadius: 16
                        )
                    )

                Image(systemName: "fork.knife")
                    .font(.system(size: 22, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 100)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(2)

                if let time = recipe.totalTimeMinutes {
                    Label("\(time) min", systemImage: "clock")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onSave) {
                    Text(isSaved ? "Saved ✓" : "Save")
                        .font(.mkCaption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSaved ? Color.mkGreen.opacity(0.12) : Color.accentColor.opacity(0.1))
                        )
                        .foregroundStyle(isSaved ? Color.mkGreen : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
            }
            .padding(10)
        }
        .glassCard(cornerRadius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(width: 160, height: 200)
    }

    private var cardGradient: LinearGradient {
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
}

// MARK: - RecipeDiscoverGrid

struct RecipeDiscoverGrid: View {
    let recipes: [HouseRecipe]
    let savedIDs: Set<String>
    let onSave: (HouseRecipe) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Recipes")
                .font(.mkHeading)
                .padding(.horizontal, 4)

            if recipes.isEmpty {
                Text("No recipes match the selected filters.")
                    .font(.mkBody)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(recipes) { recipe in
                        DiscoverGridCell(recipe: recipe, isSaved: savedIDs.contains(recipe.id)) {
                            onSave(recipe)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - DiscoverGridCell

private struct DiscoverGridCell: View {
    let recipe: HouseRecipe
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                cellGradient
                    .frame(height: 90)
                Image(systemName: "fork.knife")
                    .font(.system(size: 20, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(height: 90)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 14
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let time = recipe.totalTimeMinutes {
                        Label("\(time)m", systemImage: "clock")
                            .font(.mkCaption)
                            .foregroundStyle(.secondary)
                    }
                    if let cuisine = recipe.cuisine {
                        Text(cuisine)
                            .font(.mkCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if !recipe.dietaryTags.isEmpty {
                    TagChip(text: recipe.dietaryTags[0].localizedCapitalized, color: .mkGreen)
                }

                Button(action: onSave) {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundStyle(isSaved ? Color.mkGreen : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
            }
            .padding(10)
        }
        .glassCard(cornerRadius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var cellGradient: LinearGradient {
        let palettes: [(Color, Color)] = [
            (.accentColor.opacity(0.65), .mkLilac.opacity(0.35)),
            (.mkGreen.opacity(0.60), .teal.opacity(0.30)),
            (.mkLilac.opacity(0.70), .accentColor.opacity(0.40)),
            (.purple.opacity(0.50), .pink.opacity(0.30)),
            (.teal.opacity(0.55), .blue.opacity(0.30)),
        ]
        let idx = abs(recipe.id.hashValue) % palettes.count
        return LinearGradient(
            colors: [palettes[idx].0, palettes[idx].1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Preview

#Preview {
    let store = HouseRecipeStore()
    store.load()

    return DiscoverView(store: store, importService: ImportService(
        downloads: ModelDownloadManager(),
        inference: InferenceService(),
        whisper: WhisperTranscriptionService()
    ))
}
