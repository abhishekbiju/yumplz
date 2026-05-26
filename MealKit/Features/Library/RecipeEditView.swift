import SwiftUI
import SwiftData

// MARK: – Draft types (local-state copies, never persisted directly)

private struct IngredientDraft: Identifiable {
    let id: UUID
    var text: String
    /// `true` for rows that the user added this session and have no SwiftData counterpart yet.
    let isNew: Bool

    init(existing ingredient: Ingredient) {
        id    = ingredient.id
        text  = ingredient.originalText
        isNew = false
    }

    init() {
        id    = UUID()
        text  = ""
        isNew = true
    }
}

private struct StepDraft: Identifiable {
    let id: UUID
    var text: String
    let isNew: Bool

    init(existing step: Step) {
        id    = step.id
        text  = step.text
        isNew = false
    }

    init() {
        id    = UUID()
        text  = ""
        isNew = true
    }
}

// MARK: – RecipeEditView

/// Form-based editing screen for a `Recipe`.
///
/// All form fields are maintained as local `@State` copies.  
/// Changes are flushed to the SwiftData model **only** when the user taps "Save",
/// so "Cancel" is guaranteed to discard every edit.
struct RecipeEditView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    let recipe: Recipe

    // ── Basic info ────────────────────────────────────────────────────
    @State private var title:            String
    @State private var summary:          String
    @State private var servings:         Int
    @State private var prepTimeMinutes:  String
    @State private var cookTimeMinutes:  String
    @State private var cuisine:          String

    // ── Dietary tags ──────────────────────────────────────────────────
    @State private var isVegetarian: Bool
    @State private var isVegan:      Bool
    @State private var isGlutenFree: Bool
    @State private var isDairyFree:  Bool

    // ── Ingredients & steps ───────────────────────────────────────────
    @State private var ingredientDrafts: [IngredientDraft]
    @State private var stepDrafts:       [StepDraft]

    // ── Personal layer ────────────────────────────────────────────────
    @State private var userNotes:              String
    @State private var userRating:             Int
    @State private var updateDefaultServings:  Bool

    // MARK: init

    init(recipe: Recipe) {
        self.recipe = recipe

        _title           = State(initialValue: recipe.title)
        _summary         = State(initialValue: recipe.summary ?? "")
        _servings        = State(initialValue: recipe.servings)
        _prepTimeMinutes = State(initialValue: recipe.prepTimeSeconds.map { String($0 / 60) } ?? "")
        _cookTimeMinutes = State(initialValue: recipe.cookTimeSeconds.map { String($0 / 60) } ?? "")
        _cuisine         = State(initialValue: recipe.cuisine ?? "")

        let tags = recipe.dietaryTags
        _isVegetarian = State(initialValue: tags.contains("Vegetarian"))
        _isVegan      = State(initialValue: tags.contains("Vegan"))
        _isGlutenFree = State(initialValue: tags.contains("Gluten-Free"))
        _isDairyFree  = State(initialValue: tags.contains("Dairy-Free"))

        let sortedIngredients = (recipe.ingredients ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
        _ingredientDrafts = State(initialValue: sortedIngredients.map(IngredientDraft.init(existing:)))

        let sortedSteps = (recipe.steps ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
        _stepDrafts = State(initialValue: sortedSteps.map(StepDraft.init(existing:)))

        _userNotes             = State(initialValue: recipe.userNotes ?? "")
        _userRating            = State(initialValue: recipe.userRating ?? 0)
        _updateDefaultServings = State(initialValue: false)
    }

    // MARK: body

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                timingSection
                classificationSection
                ingredientsSection
                stepsSection
                personalSection
            }
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: – Sections

    private var basicInfoSection: some View {
        Section("Basic Info") {
            TextField("Title", text: $title)
                .font(.mkBody)

            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $summary)
                    .font(.mkBody)
                    .frame(minHeight: 72)
            }

            Stepper("Servings: \(servings)", value: $servings, in: 1...100)
                .font(.mkBody)

            Toggle("Update default servings on save", isOn: $updateDefaultServings)
                .font(.mkCaption)
                .foregroundStyle(.secondary)
        }
    }

    private var timingSection: some View {
        Section("Timing") {
            HStack {
                Text("Prep time (min)")
                    .font(.mkBody)
                Spacer()
                TextField("–", text: $prepTimeMinutes)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
            }
            HStack {
                Text("Cook time (min)")
                    .font(.mkBody)
                Spacer()
                TextField("–", text: $cookTimeMinutes)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
            }
        }
    }

    private var classificationSection: some View {
        Section("Classification") {
            TextField("Cuisine", text: $cuisine)
                .font(.mkBody)

            Group {
                Toggle("Vegetarian",  isOn: $isVegetarian)
                Toggle("Vegan",       isOn: $isVegan)
                Toggle("Gluten-Free", isOn: $isGlutenFree)
                Toggle("Dairy-Free",  isOn: $isDairyFree)
            }
            .font(.mkBody)
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach($ingredientDrafts) { $draft in
                TextField("Ingredient", text: $draft.text)
                    .font(.mkBody)
            }
            .onDelete { indexSet in
                ingredientDrafts.remove(atOffsets: indexSet)
            }
            .onMove { from, to in
                ingredientDrafts.move(fromOffsets: from, toOffset: to)
            }

            Button {
                withAnimation(.mkSnap) {
                    ingredientDrafts.append(IngredientDraft())
                }
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle.fill")
                    .font(.mkBody)
            }
        }
    }

    private var stepsSection: some View {
        Section("Steps") {
            ForEach($stepDrafts) { $draft in
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $draft.text)
                        .font(.mkBody)
                        .frame(minHeight: 56)
                }
            }
            .onDelete { indexSet in
                stepDrafts.remove(atOffsets: indexSet)
            }
            .onMove { from, to in
                stepDrafts.move(fromOffsets: from, toOffset: to)
            }

            Button {
                withAnimation(.mkSnap) {
                    stepDrafts.append(StepDraft())
                }
            } label: {
                Label("Add Step", systemImage: "plus.circle.fill")
                    .font(.mkBody)
            }
        }
    }

    private var personalSection: some View {
        Section("Personal") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $userNotes)
                    .font(.mkBody)
                    .frame(minHeight: 72)
            }

            HStack {
                Text("Rating")
                    .font(.mkBody)
                Spacer()
                StarRatingPicker(rating: $userRating)
            }
        }
    }

    // MARK: – Save

    private func save() {
        // ── Basic fields ─────────────────────────────────────────────
        recipe.title           = title
        recipe.summary         = summary.isEmpty         ? nil : summary
        recipe.cuisine         = cuisine.isEmpty         ? nil : cuisine
        recipe.prepTimeSeconds = Int(prepTimeMinutes).map { $0 * 60 }
        recipe.cookTimeSeconds = Int(cookTimeMinutes).map { $0 * 60 }
        recipe.userNotes       = userNotes.isEmpty       ? nil : userNotes
        recipe.userRating      = userRating == 0         ? nil : userRating

        if updateDefaultServings {
            recipe.servings = servings
        }

        // ── Dietary tags ─────────────────────────────────────────────
        var tags: [String] = []
        if isVegetarian { tags.append("Vegetarian") }
        if isVegan      { tags.append("Vegan") }
        if isGlutenFree { tags.append("Gluten-Free") }
        if isDairyFree  { tags.append("Dairy-Free") }
        recipe.dietaryTags = tags

        // ── Ingredients ──────────────────────────────────────────────
        let existingIngredients = recipe.ingredients ?? []
        let draftIds = Set(ingredientDrafts.filter { !$0.isNew }.map(\.id))

        // Delete removed rows
        for ingredient in existingIngredients where !draftIds.contains(ingredient.id) {
            context.delete(ingredient)
        }

        // Update existing text and re-assign orderIndex based on current position
        for (index, draft) in ingredientDrafts.enumerated() where !draft.isNew {
            if let ingredient = existingIngredients.first(where: { $0.id == draft.id }) {
                ingredient.originalText = draft.text
                ingredient.orderIndex   = index
            }
        }

        // Insert new ingredients
        for (index, draft) in ingredientDrafts.enumerated() where draft.isNew {
            let ingredient = Ingredient(originalText: draft.text, orderIndex: index)
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        // ── Steps ────────────────────────────────────────────────────
        let existingSteps  = recipe.steps ?? []
        let stepDraftIds   = Set(stepDrafts.filter { !$0.isNew }.map(\.id))

        for step in existingSteps where !stepDraftIds.contains(step.id) {
            context.delete(step)
        }

        for (index, draft) in stepDrafts.enumerated() where !draft.isNew {
            if let step = existingSteps.first(where: { $0.id == draft.id }) {
                step.text       = draft.text
                step.orderIndex = index
            }
        }

        for (index, draft) in stepDrafts.enumerated() where draft.isNew {
            let step = Step(text: draft.text, orderIndex: index)
            step.recipe = recipe
            context.insert(step)
        }

        // ── Persist ──────────────────────────────────────────────────
        recipe.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

// MARK: – StarRatingPicker

private struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = (rating == star) ? 0 : star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? Color.mkAmber : Color.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: – Preview

#if DEBUG
#Preview {
    let config    = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema    = Schema([Recipe.self, Ingredient.self, Step.self,
                            User.self, RecipeCollection.self, PlannedMeal.self,
                            GroceryList.self, GroceryItem.self])
    let container = try! ModelContainer(for: schema, configurations: [config])
    let ctx       = container.mainContext

    let recipe    = Recipe(title: "Sourdough Focaccia")
    recipe.servings = 4
    let flour = Ingredient(originalText: "500 g bread flour", orderIndex: 0)
    flour.recipe = recipe
    ctx.insert(recipe)

    return RecipeEditView(recipe: recipe)
        .modelContainer(container)
}
#endif
