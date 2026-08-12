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
#if DEBUG
            if let tabName = ProcessInfo.processInfo.environment["YUMPLZ_SCREENSHOT_TAB"] {
                selectedTab = screenshotTab(named: tabName) ?? selectedTab
            }
#endif
            houseRecipeStore.load()
            // Cold launch from Share Extension skips scenePhase onChange — drain here too.
            drainPendingImports()
            // A deep link delivered during splash (before this view mounted) posts a
            // notification nobody hears. The payload survives in the pending store, so
            // surface the Library tab to mount its consumer.
            if ShareImportDelivery.hasPendingDeepLink {
                selectedTab = .library
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                drainPendingImports()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .yumplzPendingImportLaunch)) { _ in
            drainPendingImports()
        }
        .onReceive(NotificationCenter.default.publisher(for: .yumplzImportDeepLink)) { _ in
            selectedTab = .library
        }
    }

#if DEBUG
    private func screenshotTab(named raw: String) -> Tab? {
        switch raw.lowercased() {
        case "discover": return .discover
        case "library": return .library
        case "plan": return .plan
        case "grocery": return .grocery
        case "profile": return .profile
        default: return nil
        }
    }
#endif

    // MARK: - Pending Import Draining

    private func drainPendingImports() {
        ShareImportDelivery.deliverPendingImports {
            selectedTab = .library
        }
    }
}

#Preview {
    MainTabView()
}
