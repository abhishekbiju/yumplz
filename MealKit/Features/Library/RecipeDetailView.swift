import SwiftUI
import SwiftData

// MARK: - RecipeDetailView

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddToCollection = false
    @State private var showingCookMode = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []

    var body: some View {
        ZStack {
            WarmGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection

                    VStack(alignment: .leading, spacing: 24) {
                        metadataRow

                        if !recipe.dietaryTags.isEmpty {
                            dietaryTagsRow
                        }

                        if let summary = recipe.summary {
                            sectionBlock(header: "About") {
                                Text(summary)
                                    .font(.mkBody)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                            }
                        }

                        if let ingredients = recipe.ingredients, !ingredients.isEmpty {
                            ingredientsSection(ingredients.sorted { $0.orderIndex < $1.orderIndex })
                        }

                        if let steps = recipe.steps, !steps.isEmpty {
                            stepsSection(steps.sorted { $0.orderIndex < $1.orderIndex })
                        }

                        startCookingButton
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        shareItems = buildShareItems()
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share recipe")
                    Button {
                        showingAddToCollection = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    Button {
                        recipe.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(recipe.isFavorite ? Color.red : Color.primary)
                            .animation(.mkSnap, value: recipe.isFavorite)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddToCollection) {
            AddToCollectionSheet(recipe: recipe)
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivitySheet(items: shareItems)
        }
        .fullScreenCover(isPresented: $showingCookMode) {
            NavigationStack {
                CookModeView(recipe: recipe)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingCookMode = false }
                        }
                    }
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        if let data = recipe.heroImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [.accentColor.opacity(0.5), .mkLilac.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "fork.knife")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
        }
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if let totalTime = recipe.totalTimeSeconds {
                    Label(formatTime(totalTime), systemImage: "clock")
                        .font(.mkCaption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Label(
                    "\(recipe.servings) serving\(recipe.servings == 1 ? "" : "s")",
                    systemImage: "person.2"
                )
                .font(.mkCaption.weight(.medium))
                .foregroundStyle(.secondary)

                if let cuisine = recipe.cuisine {
                    TagChip(text: cuisine)
                }
            }
            .padding(.horizontal)
        }
    }

    private var dietaryTagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recipe.dietaryTags, id: \.self) { tag in
                    TagChip(text: tag, color: .mkGreen)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Ingredients

    @ViewBuilder
    private func ingredientsSection(_ ingredients: [Ingredient]) -> some View {
        sectionBlock(header: "Ingredients") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ingredients) { ingredient in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.45))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(ingredient.originalText)
                            .font(.mkBody)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 14)
            .padding(.horizontal)
        }
    }

    // MARK: - Steps

    private func buildStepRows(_ steps: [Step]) -> [StepsListView.StepRow] {
        var count = 0
        return steps.map { step in
            let n: Int? = step.isSectionHeader ? nil : { count += 1; return count }()
            return StepsListView.StepRow(
                id: step.id,
                text: step.text,
                timerSeconds: step.timerSeconds,
                isSectionHeader: step.isSectionHeader,
                number: n
            )
        }
    }

    @ViewBuilder
    private func stepsSection(_ steps: [Step]) -> some View {
        sectionBlock(header: "Steps") {
            StepsListView(rows: buildStepRows(steps))
        }
    }

    // MARK: - Start Cooking

    private var startCookingButton: some View {
        Button {
            showingCookMode = true
        } label: {
            Text("Start Cooking")
                .font(.mkHeading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionBlock<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.mkHeading)
                .padding(.horizontal)
            content()
        }
    }

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

    // MARK: - Share

    @MainActor
    private func buildShareItems() -> [Any] {
        let text = RecipeShareFormatter.plainText(for: recipe)

        let renderer = ImageRenderer(
            content: RecipeShareCardView(recipe: recipe)
                .frame(width: 600, height: 800)
        )
        renderer.scale = 2.0

        var items: [Any] = [text]
        if let image = renderer.uiImage {
            items.append(image)
        }
        if let url = RecipeShareFormatter.deepLinkURL(for: text) {
            items.append(url)
        }
        return items
    }
}

// MARK: - Steps List View

private struct StepsListView: View {
    struct StepRow: Identifiable {
        let id: UUID
        let text: String
        let timerSeconds: Int?
        let isSectionHeader: Bool
        let number: Int?
    }

    let rows: [StepRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.id) { (row: StepRow) in
                if row.isSectionHeader {
                    Text(row.text)
                        .font(.mkCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(row.number ?? 0)")
                            .font(.mkCaption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.accentColor))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.text)
                                .font(.mkBody)
                            if let secs = row.timerSeconds {
                                Label(formatTime(secs), systemImage: "timer")
                                    .font(.mkCaption)
                                    .foregroundStyle(Color.mkLilac)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
            }
        }
        .glassCard(cornerRadius: 14)
        .padding(.horizontal)
    }

    private func formatTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

// MARK: - Activity Sheet (Share)

import UIKit

@MainActor
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Add to Collection Sheet

struct AddToCollectionSheet: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecipeCollection.orderIndex) private var collections: [RecipeCollection]

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 44, weight: .ultraLight))
                            .foregroundStyle(.secondary)
                        Text("No collections yet.\nCreate one from the Library tab.")
                            .font(.mkBody)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(collections) { collection in
                        Button {
                            toggleCollection(collection)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.accentColor)
                                Text(collection.name)
                                Spacer()
                                if isInCollection(collection) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.mkGreen)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isInCollection(_ collection: RecipeCollection) -> Bool {
        recipe.collections?.contains(where: { $0.id == collection.id }) ?? false
    }

    private func toggleCollection(_ collection: RecipeCollection) {
        if let idx = recipe.collections?.firstIndex(where: { $0.id == collection.id }) {
            recipe.collections?.remove(at: idx)
        } else {
            recipe.collections?.append(collection)
        }
        try? modelContext.save()
    }
}

// MARK: - Preview

#Preview {
    let recipe: Recipe = {
        let r = Recipe(title: "Sourdough Focaccia")
        r.summary = "A deeply flavourful focaccia with a golden crust and pillowy interior."
        r.servings = 8
        r.prepTimeSeconds = 20 * 60
        r.cookTimeSeconds = 25 * 60
        r.cuisine = "Italian"
        r.dietaryTags = ["Vegan", "Dairy-free"]
        r.isFavorite = true

        let i1 = Ingredient(originalText: "500 g bread flour", orderIndex: 0)
        let i2 = Ingredient(originalText: "10 g fine salt", orderIndex: 1)
        let i3 = Ingredient(originalText: "7 g instant yeast", orderIndex: 2)
        r.ingredients = [i1, i2, i3]

        let s1 = Step(text: "Mix flour, salt and yeast in a large bowl.", orderIndex: 0)
        let s2 = Step(text: "Add 400 ml warm water and 4 tbsp olive oil. Mix to combine.", orderIndex: 1)
        let s3 = Step(text: "Bake at 220 °C for 25 minutes.", orderIndex: 2, timerSeconds: 25 * 60)
        r.steps = [s1, s2, s3]
        return r
    }()

    NavigationStack {
        RecipeDetailView(recipe: recipe)
    }
    .modelContainer(for: [Recipe.self, RecipeCollection.self], inMemory: true)
}
