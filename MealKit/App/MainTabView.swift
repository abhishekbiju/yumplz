import SwiftUI

/// The 5-tab bottom bar that hosts every top-level surface after auth.
/// Services (ModelDownloadManager, ImportService, etc.) are created once here
/// and passed down as dependencies so they share a single lifecycle.
struct MainTabView: View {
    @State private var selectedTab: Tab = .discover

    // Services created once, shared across all tabs.
    @State private var downloads = ModelDownloadManager()
    @State private var inference = InferenceService()
    @State private var whisper  = WhisperTranscriptionService()

    // ImportService is derived from the above three.
    @State private var importService: ImportService?

    enum Tab: Hashable {
        case discover, library, plan, grocery, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoverView()
                .tag(Tab.discover)
                .tabItem { Label("Discover", systemImage: "sparkles") }

            if let importService {
                LibraryView(downloads: downloads, importService: importService)
                    .tag(Tab.library)
                    .tabItem { Label("Library", systemImage: "books.vertical") }
            } else {
                ProgressView()
                    .tag(Tab.library)
                    .tabItem { Label("Library", systemImage: "books.vertical") }
            }

            PlanView()
                .tag(Tab.plan)
                .tabItem { Label("Plan", systemImage: "calendar") }

            GroceryView()
                .tag(Tab.grocery)
                .tabItem { Label("Grocery", systemImage: "cart") }

            ProfileView()
                .tag(Tab.profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
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
        }
    }
}

#Preview {
    MainTabView()
}
