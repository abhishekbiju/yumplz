import SwiftUI
import SwiftData

/// Shows recipes belonging to a user-created `RecipeCollection`.
struct CollectionBrowseView: View {
    let collection: RecipeCollection
    var downloads: ModelDownloadManager
    var importService: ImportService

    @Query(sort: \Recipe.createdAt, order: .reverse) private var allRecipes: [Recipe]
    @Environment(\.modelContext) private var modelContext

    @State private var importPresentation: ImportPresentationRequest?
    @State private var recipePendingDeletion: Recipe?

    private var memberRecipes: [Recipe] {
        collection.recipes ?? []
    }

    private var suggestedRecipes: [Recipe] {
        let members = Set(memberRecipes.map(\.id))
        return Array(allRecipes.filter { !members.contains($0.id) }.prefix(5))
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            WarmGlassBackground()

            if memberRecipes.isEmpty {
                emptyCollectionContent
            } else {
                recipeGrid(memberRecipes)
            }

            ImportRecipeFAB {
                importPresentation = .newImport
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeDetailView(recipe: recipe)
        }
        .sheet(item: $importPresentation) { presentation in
            ImportSheetView(
                downloads: downloads,
                importService: importService,
                initialPasteText: presentation.route.pasteText,
                initialImportURL: presentation.route.importURL,
                initialVideoPath: presentation.route.videoPath,
                autoStartImport: presentation.route.autoStartImport,
                shareExtractionMode: presentation.route.extractionMode
            )
        }
        .recipeDeleteConfirmation(recipe: $recipePendingDeletion)
    }

    // MARK: - Empty collection

    private var emptyCollectionContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                    Text("No recipes in this collection")
                        .font(.mkHeading)
                    Text("Tap the purple + button to import a recipe, or add one from your library below.")
                        .font(.mkBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Button {
                        importPresentation = .newImport
                    } label: {
                        Label("Import recipe", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
                .padding(.top, 32)

                if !suggestedRecipes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add from your library")
                            .font(.mkHeading)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(suggestedRecipes) { recipe in
                                VStack(spacing: 8) {
                                    if recipe.isImportInteractive {
                                        NavigationLink(value: recipe) {
                                            RecipeCardView(recipe: recipe)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        RecipeCardView(recipe: recipe)
                                    }

                                    Button {
                                        addToCollection(recipe)
                                    } label: {
                                        Label("Add to collection", systemImage: "plus")
                                            .font(.mkCaption.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Grid

    private func recipeGrid(_ recipes: [Recipe]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(recipes) { recipe in
                    if recipe.isImportInteractive {
                        NavigationLink(value: recipe) {
                            RecipeCardView(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                recipePendingDeletion = recipe
                            } label: {
                                Label("Delete Recipe", systemImage: "trash")
                            }
                        }
                    } else {
                        RecipeCardView(recipe: recipe)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
    }

    private func addToCollection(_ recipe: Recipe) {
        collection.addRecipe(recipe)
        try? modelContext.save()
    }
}

#Preview {
    let collection = RecipeCollection(name: "Dinners")
    let r1 = Recipe(title: "Pasta e Fagioli")
    r1.cookTimeSeconds = 30 * 60
    r1.cuisine = "Italian"
    collection.recipes = [r1]

    return NavigationStack {
        CollectionBrowseView(
            collection: collection,
            downloads: ModelDownloadManager(),
            importService: ImportService(
                downloads: ModelDownloadManager(),
                inference: InferenceService(),
                whisper: WhisperTranscriptionService()
            )
        )
    }
    .modelContainer(for: [Recipe.self, RecipeCollection.self], inMemory: true)
}
