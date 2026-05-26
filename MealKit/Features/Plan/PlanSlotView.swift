import SwiftUI
import SwiftData

struct PlanSlotView: View {
    let slot: Slot
    let date: Date
    let meals: [PlannedMeal]
    let isPastDay: Bool

    @Environment(\.modelContext) private var context

    @State private var showAddSheet = false
    @State private var showRecipePicker = false
    @State private var showNoteAlert = false
    @State private var noteInput = ""
    @State private var editingServingsMeal: PlannedMeal? = nil
    @State private var editingServingsValue = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label(slot.displayName, systemImage: slot.systemImage)
                    .font(.mkHeading)
                    .foregroundStyle(.primary)
                Spacer()
                if !isPastDay {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if meals.isEmpty {
                Text("Nothing planned")
                    .font(.mkCaption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(meals) { meal in
                    MealRow(meal: meal, onMarkCooked: { markAsCooked(meal) }, onRemove: { removeMeal(meal) }, onEditServings: {
                        editingServingsMeal = meal
                        editingServingsValue = meal.plannedServings ?? meal.recipe?.servings ?? 1
                    })
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
        // Add-meal action sheet
        .confirmationDialog("Add to \(slot.displayName)", isPresented: $showAddSheet, titleVisibility: .visible) {
            Button("From Library") { showRecipePicker = true }
            Button("Note only") { showNoteAlert = true }
            Button("Cancel", role: .cancel) {}
        }
        // Recipe picker sheet
        .sheet(isPresented: $showRecipePicker) {
            RecipePickerSheet { recipe in
                addMeal(recipe: recipe)
                showRecipePicker = false
            }
        }
        // Note alert
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("e.g. Leftovers", text: $noteInput)
            Button("Add") { addNote() }
            Button("Cancel", role: .cancel) { noteInput = "" }
        }
        // Edit servings alert
        .alert("Edit Servings", isPresented: Binding(
            get: { editingServingsMeal != nil },
            set: { if !$0 { editingServingsMeal = nil } }
        )) {
            Stepper("\(editingServingsValue) serving\(editingServingsValue == 1 ? "" : "s")",
                    value: $editingServingsValue, in: 1...99)
            Button("Save") {
                editingServingsMeal?.plannedServings = editingServingsValue
                try? context.save()
                editingServingsMeal = nil
            }
            Button("Cancel", role: .cancel) { editingServingsMeal = nil }
        }
    }

    private func addMeal(recipe: Recipe) {
        let meal = PlannedMeal(date: date, slot: slot, recipe: recipe)
        meal.plannedServings = recipe.servings
        context.insert(meal)
        try? context.save()
    }

    private func addNote() {
        let trimmed = noteInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { noteInput = ""; return }
        let meal = PlannedMeal(date: date, slot: slot, noteText: trimmed)
        context.insert(meal)
        try? context.save()
        noteInput = ""
    }

    private func markAsCooked(_ meal: PlannedMeal) {
        meal.isCooked = true
        meal.cookedAt = Date()
        if let recipe = meal.recipe {
            recipe.timesCooked += 1
            recipe.lastCookedAt = Date()
        }
        try? context.save()
    }

    private func removeMeal(_ meal: PlannedMeal) {
        context.delete(meal)
        try? context.save()
    }
}

// MARK: - MealRow

private struct MealRow: View {
    let meal: PlannedMeal
    let onMarkCooked: () -> Void
    let onRemove: () -> Void
    let onEditServings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.mkSurface)
                    .frame(width: 40, height: 40)
                Image(systemName: meal.isNoteOnly ? "note.text" : "fork.knife")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.isNoteOnly ? (meal.noteText ?? "Note") : (meal.recipe?.title ?? "Recipe"))
                    .font(.mkBody)
                    .lineLimit(1)
                if !meal.isNoteOnly, let servings = meal.plannedServings {
                    Text("\(servings) serving\(servings == 1 ? "" : "s")")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if meal.isCooked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.mkGreen)
            }

            Menu {
                if !meal.isCooked {
                    Button {
                        onMarkCooked()
                    } label: {
                        Label("Mark as Cooked", systemImage: "checkmark.circle")
                    }
                }
                if !meal.isNoteOnly {
                    Button {
                        onEditServings()
                    } label: {
                        Label("Edit Servings", systemImage: "person.2")
                    }
                }
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.mkSurface.opacity(0.5))
        )
        .opacity(meal.isCooked ? 0.6 : 1.0)
    }
}

// MARK: - RecipePickerSheet

struct RecipePickerSheet: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    let onSelect: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(recipes) { recipe in
                Button {
                    onSelect(recipe)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.title)
                            .font(.mkBody)
                            .foregroundStyle(.primary)
                        if let time = recipe.totalTimeSeconds {
                            Text("\(time / 60) min")
                                .font(.mkCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
