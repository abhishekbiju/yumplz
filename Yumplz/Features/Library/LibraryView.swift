import SwiftUI
import SwiftData

// MARK: - Navigation destination type

enum LibraryDestination: Hashable {
    case system(SystemCollection)
    case userCollection(PersistentIdentifier)
}

// MARK: - LibraryView

struct LibraryView: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \RecipeCollection.orderIndex) private var collections: [RecipeCollection]
    @Environment(\.modelContext) private var modelContext

    @State private var searchVM = LibrarySearchViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var importPresentation: ImportPresentationRequest?
    @State private var showingNewCollectionAlert = false
    @State private var pendingManualRecipe: Recipe? = nil
    @State private var newCollectionName = ""
    @State private var collectionToRename: RecipeCollection?
    @State private var renameText = ""
    @State private var recipePendingDeletion: Recipe?

    var downloads: ModelDownloadManager
    var importService: ImportService

    private let dietaryOptions = ["Vegetarian", "Vegan", "Gluten-Free", "Dairy-Free"]
    private let gridColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var filteredRecipes: [Recipe] {
        searchVM.filter(recipes)
    }

    private var cookTimeLabel: String {
        switch searchVM.maxCookTimeSeconds {
        case nil:  return "Any time"
        case 1800: return "≤ 30 min"
        case 3600: return "≤ 1 hr"
        default:
            let mins = (searchVM.maxCookTimeSeconds ?? 0) / 60
            return "≤ \(mins) min"
        }
    }

    var body: some View {
        @Bindable var bvm = searchVM
        NavigationStack(path: $navigationPath) {
            ZStack {
                WarmGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Filter chip bar
                        filterBar

                        // System Collections strip (Issue #9)
                        systemCollectionsStrip
                            .padding(.top, 20)

                        // User Collections list (Issue #9)
                        userCollectionsSection
                            .padding(.top, 24)

                        // All Recipes section
                        allRecipesSection
                            .padding(.top, 24)
                    }
                }
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe)
                }
                .navigationDestination(for: LibraryDestination.self) { destination in
                    switch destination {
                    case .system(let sc):
                        RecipeGridView(recipes: sc.filter(recipes), title: sc.displayName)
                    case .userCollection(let id):
                        if let col = collections.first(where: { $0.persistentModelID == id }) {
                            CollectionBrowseView(
                                collection: col,
                                downloads: downloads,
                                importService: importService
                            )
                        }
                    }
                }

                importFAB
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newCollectionName = ""
                        showingNewCollectionAlert = true
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .accessibilityLabel("New collection")
                }
            }
        }
        .searchable(text: $bvm.query, prompt: "Search recipes, cuisines, tags…")
        .sheet(item: $importPresentation) { presentation in
            ImportSheetView(
                downloads: downloads,
                importService: importService,
                onManualEntry: { recipe in
                    pendingManualRecipe = recipe
                },
                initialPasteText: presentation.route.pasteText,
                initialImportURL: presentation.route.importURL,
                initialVideoPath: presentation.route.videoPath,
                autoStartImport: presentation.route.autoStartImport,
                shareExtractionMode: presentation.route.extractionMode
            )
        }
        .onChange(of: importPresentation) { _, newValue in
            // Navigate to the manually-created recipe once the sheet fully dismisses.
            if newValue == nil, let recipe = pendingManualRecipe {
                navigationPath.append(recipe)
                pendingManualRecipe = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .yumplzImportDeepLink)) { note in
            guard let text = note.object as? String else { return }
            let request = ImportDeepLinkRouter.presentationRequest(
                payload: text,
                userInfo: note.userInfo
            )
            // Avoid cancelling in-flight imports by re-presenting the exact same route.
            if importPresentation?.route != request.route {
                importPresentation = request
            }
            // If we handled a live notification, prevent onAppear from replaying
            // the same payload from the pending store.
            ShareImportDelivery.clearPendingDeepLink()
        }
        .onAppear {
            if let pending = ShareImportDelivery.consumePendingDeepLink() {
                if importPresentation?.route != pending.route {
                    importPresentation = pending
                }
            }
        }
        .alert("New Collection", isPresented: $showingNewCollectionAlert) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") { createCollection() }
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        }
        .alert(
            "Rename Collection",
            isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) { collectionToRename = nil }
        }
        .recipeDeleteConfirmation(recipe: $recipePendingDeletion)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("Any time") { searchVM.maxCookTimeSeconds = nil }
                    Button("≤ 30 min") { searchVM.maxCookTimeSeconds = 1800 }
                    Button("≤ 1 hr")   { searchVM.maxCookTimeSeconds = 3600 }
                } label: {
                    TagChip(
                        text: cookTimeLabel,
                        color: searchVM.maxCookTimeSeconds != nil ? .accentColor : .secondary
                    )
                }

                ForEach(dietaryOptions, id: \.self) { tag in
                    let active = searchVM.selectedDietaryTags.contains(tag)
                    Button {
                        if active { searchVM.selectedDietaryTags.remove(tag) }
                        else      { searchVM.selectedDietaryTags.insert(tag) }
                    } label: {
                        TagChip(text: tag, color: active ? .mkGreen : .secondary)
                    }
                }

                if searchVM.hasActiveFilters {
                    Button {
                        withAnimation(.mkSnap) { searchVM.clearAll() }
                    } label: {
                        TagChip(text: "Clear", color: .accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    // MARK: - System Collections Strip

    private var systemCollectionsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collections")
                .font(.mkHeading)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SystemCollection.allCases) { sc in
                        NavigationLink(value: LibraryDestination.system(sc)) {
                            HStack(spacing: 6) {
                                Image(systemName: sc.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(sc.displayName)
                                    .font(.mkCaption.weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassCard(cornerRadius: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - User Collections

    private var userCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Collections")
                .font(.mkHeading)
                .padding(.horizontal, 20)

            if collections.isEmpty {
                Text("No collections yet. Tap the folder+ icon above to create one.")
                    .font(.mkBody)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(collections) { collection in
                        NavigationLink(value: LibraryDestination.userCollection(collection.persistentModelID)) {
                            userCollectionRow(collection)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                collectionToRename = collection
                                renameText = collection.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                modelContext.delete(collection)
                                try? modelContext.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - All Recipes

    @ViewBuilder
    private var allRecipesSection: some View {
        if filteredRecipes.isEmpty && recipes.isEmpty {
            emptyLibraryState
        } else if filteredRecipes.isEmpty {
            noResultsState
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("All Recipes")
                    .font(.mkHeading)
                    .padding(.horizontal, 20)

                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(filteredRecipes) { recipe in
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
                .padding(.bottom, 110)
            }
        }
    }

    // MARK: - Empty States

    private var emptyLibraryState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 32)
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Your library is empty")
                .font(.mkHeading)
            Text("Tap the purple + button to import your first recipe.")
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(minHeight: 200)
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 32)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No recipes match")
                .font(.mkHeading)
            Text("Try adjusting your filters or search term.")
                .font(.mkBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Clear filters") {
                withAnimation(.mkSnap) { searchVM.clearAll() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            Spacer()
        }
        .padding()
        .frame(minHeight: 200)
    }

    // MARK: - FAB

    private var importFAB: some View {
        ImportRecipeFAB {
            importPresentation = .newImport
        }
    }

    private func userCollectionRow(_ collection: RecipeCollection) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.mkPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                Text(collectionInitial(collection.name))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.mkBody.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(collectionCountLabel(collection))
                    .font(.mkCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    private func collectionInitial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private func collectionCountLabel(_ collection: RecipeCollection) -> String {
        let count = collection.recipeCount
        switch count {
        case 0: return "No recipes yet"
        case 1: return "1 recipe"
        default: return "\(count) recipes"
        }
    }

    // MARK: - Actions

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let col = RecipeCollection(name: name, orderIndex: collections.count)
        RecipeCollection.seedNewCollection(col, from: recipes)
        modelContext.insert(col)
        try? modelContext.save()
        newCollectionName = ""
    }

    private func saveRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let col = collectionToRename else { return }
        col.name = name
        try? modelContext.save()
        collectionToRename = nil
    }
}

#Preview {
    LibraryView(
        downloads: ModelDownloadManager(),
        importService: ImportService(
            downloads: ModelDownloadManager(),
            inference: InferenceService(),
            whisper: WhisperTranscriptionService()
        )
    )
    .modelContainer(for: [Recipe.self, RecipeCollection.self], inMemory: true)
}
