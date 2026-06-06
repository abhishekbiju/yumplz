import SwiftUI
import SwiftData

/// 2-column lazy grid of recipe cards. Handles empty-state and navigation to
/// `RecipeDetailView`. Parent `NavigationStack` is expected but this view also
/// declares its own `navigationDestination` so it works standalone when pushed.
struct RecipeGridView: View {
    let recipes: [Recipe]
    var title: String = "Recipes"

    @State private var recipePendingDeletion: Recipe?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            WarmGlassBackground()

            if recipes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
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
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            recipePendingDeletion = recipe
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Recipe.self) { recipe in
            RecipeDetailView(recipe: recipe)
        }
        .recipeDeleteConfirmation(recipe: $recipePendingDeletion)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("No recipes yet. Tap + to import your first one.")
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

#Preview {
    NavigationStack {
        RecipeGridView(recipes: [], title: "Favorites")
    }
}
