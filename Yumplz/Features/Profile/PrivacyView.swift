import SwiftUI
import SwiftData

struct PrivacyView: View {
    @Environment(\.modelContext)          private var context
    @Environment(UserPreferencesStore.self) private var prefs
    @Environment(AuthenticationManager.self) private var auth

    @State private var showDeleteConfirmation = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var exportError: String?

    var body: some View {
        PurpleScreenContainer {
            List {
            Section("Export") {
                Button("Export my recipes") {
                    exportRecipes()
                }
            }

            if let error = exportError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Button("Delete All My Data", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
            }
            .mkInsetListStyle()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Delete All Your Data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your recipes, meal plans, and grocery lists. This cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
    }

    // MARK: - Export

    private struct RecipeJSON: Encodable {
        let title: String
        let cuisine: String?
        let servings: Int
        let ingredients: [IngredientJSON]
        let steps: [StepJSON]
        let tags: [String]
        let dietaryTags: [String]

        struct IngredientJSON: Encodable { let originalText: String }
        struct StepJSON: Encodable        { let text: String }
    }

    private func exportRecipes() {
        do {
            let recipes = try context.fetch(FetchDescriptor<Recipe>())
            let payload = recipes.map { r in
                RecipeJSON(
                    title: r.title,
                    cuisine: r.cuisine,
                    servings: r.servings,
                    ingredients: (r.ingredients ?? [])
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .map { RecipeJSON.IngredientJSON(originalText: $0.originalText) },
                    steps: (r.steps ?? [])
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .map { RecipeJSON.StepJSON(text: $0.text) },
                    tags: r.tags,
                    dietaryTags: r.dietaryTags
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("yumplz-recipes.json")
            try data.write(to: url, options: .atomic)

            shareItems = [url]
            showShareSheet = true
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Delete all data

    private func deleteAllData() {
        do {
            try context.delete(model: Recipe.self)
            try context.delete(model: RecipeCollection.self)
            try context.delete(model: PlannedMeal.self)
            try context.delete(model: GroceryList.self)
            try context.delete(model: GroceryItem.self)
            try context.save()
        } catch {
            // Best-effort; proceed to clear prefs and sign out regardless.
        }

        let keys: [String] = [
            "com.abhishekbiju.yumplz.dietaryDefaults",
            "com.abhishekbiju.yumplz.storeCategoryOrder",
            "com.abhishekbiju.yumplz.mealReminderEnabled",
            "com.abhishekbiju.yumplz.mealReminderHour",
            "com.abhishekbiju.yumplz.mealReminderMinute",
            "com.abhishekbiju.yumplz.appearancePreference",
        ]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }

        auth.signOut()
    }
}

// MARK: - UIKit share sheet bridge

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
