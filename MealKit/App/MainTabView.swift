import SwiftUI

/// The 5-tab bottom bar that hosts every top-level surface after auth.
/// Services (ModelDownloadManager, ImportService, etc.) are created once here
/// and passed down as dependencies so they share a single lifecycle.
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .discover

    // Services created once, shared across all tabs.
    @State private var downloads = ModelDownloadManager()
    @State private var inference = InferenceService()
    @State private var whisper  = WhisperTranscriptionService()
    @State private var prefs    = UserPreferencesStore()

    // ImportService is derived from the above three.
    @State private var importService: ImportService?

    // House Recipes for the Discover tab.
    @State private var houseRecipeStore = HouseRecipeStore()

    enum Tab: Hashable {
        case discover, library, plan, grocery, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            if let importService {
                DiscoverView(store: houseRecipeStore, importService: importService)
                    .tag(Tab.discover)
                    .tabItem { Label("Discover", systemImage: "sparkles") }
            } else {
                ProgressView()
                    .tag(Tab.discover)
                    .tabItem { Label("Discover", systemImage: "sparkles") }
            }

            if let importService {
                LibraryView(downloads: downloads, importService: importService)
                    .tag(Tab.library)
                    .tabItem { Label("Library", systemImage: "books.vertical") }
            } else {
                ProgressView()
                    .tag(Tab.library)
                    .tabItem { Label("Library", systemImage: "books.vertical") }
            }

            PlanView(downloads: downloads, inference: inference)
                .tag(Tab.plan)
                .tabItem { Label("Plan", systemImage: "calendar") }

            GroceryView()
                .tag(Tab.grocery)
                .tabItem { Label("Grocery", systemImage: "cart") }

            ProfileView()
                .tag(Tab.profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .environment(prefs)
        .tint(.accentColor)
        .task {
            // Wire ImportService once on first appearance.
            if importService == nil {
                importService = ImportService(
                    downloads: downloads,
                    inference: inference,
                    whisper: whisper
                )
            }
            houseRecipeStore.load()
        }
        .onChange(of: scenePhase) { _, phase in
            // Drain the Share Extension queue each time the app foregrounds.
            if phase == .active {
                drainPendingImports()
            }
        }
    }

    // MARK: - Pending Import Draining

    /// Drains the Share Extension queue and fires one deep-link notification
    /// per item. LibraryView observes `.mealKitImportDeepLink` and opens the
    /// import sheet pre-populated with the URL — the same path used by
    /// `mealkit://import?text=…` deep links.
    private func drainPendingImports() {
        let pending = PendingImportStore.drain()
        guard !pending.isEmpty else { return }

        // Switch to Library so the import sheet appears in the right tab.
        selectedTab = .library

        // Fire notifications with a small delay between each to avoid race
        // conditions when multiple items were queued.
        for (index, item) in pending.enumerated() {
            let delay = Double(index) * 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                switch item.kind {
                case .url:
                    NotificationCenter.default.post(
                        name: .mealKitImportDeepLink,
                        object: item.value
                    )
                case .videoFile:
                    NotificationCenter.default.post(
                        name: .mealKitImportDeepLink,
                        object: "file://\(item.value)"
                    )
                }
            }
        }
    }
}

#Preview {
    MainTabView()
}
