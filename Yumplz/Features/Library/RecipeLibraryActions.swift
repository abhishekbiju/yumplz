import SwiftData
import SwiftUI

/// Shared delete flow for recipes shown in Library grids and detail.
enum RecipeLibraryActions {

    static func plannedMealCount(for recipe: Recipe) -> Int {
        recipe.plannedMeals?.count ?? 0
    }

    static func deleteMessage(for recipe: Recipe) -> String {
        let count = plannedMealCount(for: recipe)
        if count > 0 {
            return "This recipe is on \(count) meal plan slot\(count == 1 ? "" : "s"). "
                + "Deleting it removes those planned meals. This cannot be undone."
        }
        return "This recipe will be permanently deleted. This cannot be undone."
    }

    static func delete(_ recipe: Recipe, in context: ModelContext) {
        context.delete(recipe)
        try? context.save()
    }
}

/// Confirmation alert bound to an optional recipe pending deletion.
struct RecipeDeleteConfirmationModifier: ViewModifier {
    @Binding var recipePendingDeletion: Recipe?
    var onDeleted: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.alert(
            "Delete Recipe?",
            isPresented: Binding(
                get: { recipePendingDeletion != nil },
                set: { if !$0 { recipePendingDeletion = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let recipe = recipePendingDeletion else { return }
                RecipeLibraryActions.delete(recipe, in: modelContext)
                recipePendingDeletion = nil
                onDeleted?()
            }
            Button("Cancel", role: .cancel) {
                recipePendingDeletion = nil
            }
        } message: {
            if let recipe = recipePendingDeletion {
                Text(RecipeLibraryActions.deleteMessage(for: recipe))
            }
        }
    }
}

extension View {
    func recipeDeleteConfirmation(
        recipe: Binding<Recipe?>,
        onDeleted: (() -> Void)? = nil
    ) -> some View {
        modifier(RecipeDeleteConfirmationModifier(recipePendingDeletion: recipe, onDeleted: onDeleted))
    }
}
