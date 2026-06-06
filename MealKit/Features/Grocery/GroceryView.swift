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
    @State private var showAddItemSheet = false
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
            .navigationTitle(activeList?.name ?? "Grocery")
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
                        .accessibilityLabel("Past lists")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showGenerateSheet = true
                            } label: {
                                Label("Regenerate from plan", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button(role: .destructive) {
                                archiveActiveList()
                            } label: {
                                Label("Archive list", systemImage: "archivebox")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if activeList != nil {
                    Button {
                        manualItemName = ""
                        showAddItemSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(GradientFABStyle())
                    .accessibilityLabel("Add grocery item")
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showGenerateSheet) {
            generateSheet
        }
        .sheet(isPresented: $showArchivedSheet) {
            archivedListsSheet
        }
        .sheet(isPresented: $showAddItemSheet) {
            if let list = activeList {
                addItemSheet(list: list)
            }
        }
    }

    // MARK: - Active list

    private func activeListView(_ list: GroceryList) -> some View {
        let items = list.items ?? []
        let unchecked = items.filter { !$0.isChecked }
        let checked = items.filter { $0.isChecked }
        let uncheckedCount = unchecked.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary strip
                HStack(spacing: 12) {
                    summaryPill(
                        value: "\(uncheckedCount)",
                        label: "to buy",
                        icon: "cart"
                    )
                    summaryPill(
                        value: "\(checked.count)",
                        label: "done",
                        icon: "checkmark.circle"
                    )
                }
                .padding(.horizontal, 16)

                // Unchecked by store category
                ForEach(prefs.storeCategoryOrder, id: \.self) { cat in
                    let catItems = unchecked.filter { $0.storeCategory == cat }
                    if !catItems.isEmpty {
                        grocerySection(title: cat.displayName, items: catItems)
                    }
                }

                // Items with unknown/other category not in order list
                let orderedCats = Set(prefs.storeCategoryOrder)
                let uncategorized = unchecked.filter { !orderedCats.contains($0.storeCategory) }
                if !uncategorized.isEmpty {
                    grocerySection(title: "Other", items: uncategorized)
                }

                if !checked.isEmpty {
                    grocerySection(title: "Done", items: checked, dimmed: true)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
    }

    private func grocerySection(title: String, items: [GroceryItem], dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.mkCaption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    GroceryItemRow(item: item)
                        .opacity(dimmed ? 0.75 : 1)
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 4)
            .glassCard(cornerRadius: 16)
            .padding(.horizontal, 16)
        }
    }

    private func summaryPill(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.mkHeading)
                Text(label)
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "cart")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            Text("No grocery list")
                .font(.mkHeading)
            Text("Generate a list from your meal plan, then add extras with the + button.")
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showGenerateSheet = true
            } label: {
                Label("Generate from plan", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
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

    // MARK: - Add item sheet

    private func addItemSheet(list: GroceryList) -> some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Item name")
                            .font(.mkCaption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. Olive oil", text: $manualItemName)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit { addManualItem(to: list) }
                    }
                    .padding(16)
                    .glassCard()

                    Button {
                        addManualItem(to: list)
                        showAddItemSheet = false
                    } label: {
                        Label("Add to list", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualItemName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddItemSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Generate sheet

    private var generateSheet: some View {
        NavigationStack {
            ZStack {
                WarmGlassBackground()
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Generate Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
            ZStack {
                WarmGlassBackground()
                List(archivedLists) { list in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(list.name)
                            .font(.mkBody)
                        Text("\(list.items?.count ?? 0) items")
                            .font(.mkCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .mkInsetListStyle()
            }
            .navigationTitle("Past Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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
        HStack(spacing: 12) {
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

            Text(IngredientEmojiMapper.emoji(for: item))
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.capitalized)
                    .font(.mkBody.weight(.medium))
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)
                if !quantityLabel.isEmpty {
                    Text(quantityLabel)
                        .font(.mkCaption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if item.isManual {
                Text("manual")
                    .font(.mkCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    GroceryView()
        .modelContainer(for: [GroceryList.self, GroceryItem.self, PlannedMeal.self, Recipe.self], inMemory: true)
}
