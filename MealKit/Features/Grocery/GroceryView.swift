import SwiftUI
import SwiftData

struct GroceryView: View {
    @Query(
        filter: #Predicate<GroceryList> { !$0.isArchived },
        sort: \GroceryList.createdAt,
        order: .reverse
    ) private var activeLists: [GroceryList]

    @Query(
        filter: #Predicate<GroceryList> { $0.isArchived },
        sort: \GroceryList.createdAt,
        order: .reverse
    ) private var archivedLists: [GroceryList]

    @Environment(\.modelContext)            private var context
    @Environment(UserPreferencesStore.self) private var prefs

    @State private var showGenerateSheet = false
    @State private var showArchivedSheet = false
    @State private var generateStartDate = Date()
    @State private var generateEndDate: Date = Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date()
    @State private var manualItemName = ""
    @State private var generateError: String? = nil

    private var activeList: GroceryList? { activeLists.first }

    var body: some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()

                if let list = activeList {
                    activeListView(list)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Grocery")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if activeList != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showArchivedSheet = true
                        } label: {
                            Image(systemName: "archivebox")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Archive") {
                            archiveActiveList()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showGenerateSheet) {
            generateSheet
        }
        .sheet(isPresented: $showArchivedSheet) {
            archivedListsSheet
        }
    }

    // MARK: - Active list

    private func activeListView(_ list: GroceryList) -> some View {
        let items = list.items ?? []
        let unchecked = items.filter { !$0.isChecked }
        let checked = items.filter { $0.isChecked }

        return List {
            // Unchecked grouped by category
            ForEach(prefs.storeCategoryOrder, id: \.self) { cat in
                let catItems = unchecked.filter { $0.storeCategory == cat }
                if !catItems.isEmpty {
                    Section(cat.displayName) {
                        ForEach(catItems) { item in
                            GroceryItemRow(item: item)
                        }
                    }
                }
            }

            // Checked "Done" section
            if !checked.isEmpty {
                Section("Done") {
                    ForEach(checked) { item in
                        GroceryItemRow(item: item)
                    }
                }
            }

            // Add manual item row
            Section {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                    TextField("Add item…", text: $manualItemName)
                        .onSubmit { addManualItem(to: list) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(list.name)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No grocery list")
                .font(.mkHeading)
            Text("Generate a list from your meal plan.")
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Generate list") {
                showGenerateSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            if !archivedLists.isEmpty {
                Button("View past lists") { showArchivedSheet = true }
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Generate sheet

    private var generateSheet: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    DatePicker("Start", selection: $generateStartDate, displayedComponents: .date)
                    DatePicker("End", selection: $generateEndDate, in: generateStartDate..., displayedComponents: .date)
                }
                if let error = generateError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.mkCaption)
                    }
                }
            }
            .navigationTitle("Generate Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showGenerateSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        do {
                            try generateList()
                        } catch {
                            generateError = error.localizedDescription
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Archived lists sheet

    private var archivedListsSheet: some View {
        NavigationStack {
            List(archivedLists) { list in
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.mkBody)
                    Text("\(list.items?.count ?? 0) items")
                        .font(.mkCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Past Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showArchivedSheet = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func generateList() throws {
        let cal = Calendar.current
        let start = cal.startOfDay(for: generateStartDate)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: generateEndDate)) ?? generateEndDate

        let allMeals = try context.fetch(FetchDescriptor<PlannedMeal>())
        let inRange = allMeals.filter { $0.date >= start && $0.date < end }
        let pairs = inRange.map { (meal: $0, recipe: $0.recipe as Recipe?) }

        let aggregated = GroceryAggregator.aggregate(meals: pairs)

        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let listName = "\(f.string(from: generateStartDate)) – \(f.string(from: generateEndDate))"
        let list = GroceryList(name: listName, startDate: generateStartDate, endDate: generateEndDate)
        context.insert(list)

        for (index, item) in aggregated.enumerated() {
            let groceryItem = GroceryItem(
                name: item.name.capitalized,
                quantity: item.quantity,
                unit: item.unit,
                storeCategory: item.storeCategory
            )
            groceryItem.customUnit = item.customUnit
            groceryItem.orderIndex = index
            groceryItem.list = list
            context.insert(groceryItem)
        }

        try context.save()
        generateError = nil
        showGenerateSheet = false
    }

    private func archiveActiveList() {
        activeList?.isArchived = true
        try? context.save()
    }

    private func addManualItem(to list: GroceryList) {
        let trimmed = manualItemName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let item = GroceryItem(name: trimmed, isManual: true)
        item.orderIndex = (list.items?.count ?? 0)
        item.list = list
        context.insert(item)
        try? context.save()
        manualItemName = ""
    }
}

// MARK: - GroceryItemRow

private struct GroceryItemRow: View {
    @Bindable var item: GroceryItem
    @Environment(\.modelContext) private var context

    private var quantityLabel: String {
        var parts: [String] = []
        if let qty = item.quantity {
            let s = qty.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(qty))
                : String(format: "%.1f", qty)
            parts.append(s)
        }
        if let unit = item.unit {
            parts.append(unit.rawValue)
        } else if let cu = item.customUnit {
            parts.append(cu)
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        HStack {
            Button {
                withAnimation(.mkSnap) {
                    item.isChecked.toggle()
                    try? context.save()
                }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isChecked ? Color.mkGreen : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.capitalized)
                    .font(.mkBody)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if !quantityLabel.isEmpty {
                    Text(quantityLabel)
                        .font(.mkCaption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if item.isManual {
                Text("manual")
                    .font(.mkCaption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    GroceryView()
        .modelContainer(for: [GroceryList.self, GroceryItem.self, PlannedMeal.self, Recipe.self], inMemory: true)
}
