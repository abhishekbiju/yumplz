import SwiftUI

/// Discover tab — the front of the magazine. Will host the daily hero, editorial
/// rails, personalised rails, and browse-by-cuisine/meal/dietary grids (Q13).
///
/// Reads from the Content Library (mirrored in CloudKit Public per ADR 0002).
struct DiscoverView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderSurface(
                    title: "Discover",
                    subtitle: "Daily hero · editorial rails · browse by cuisine · House Recipes.",
                    systemImage: "sparkles",
                    progress: "Q13 — pending Content Library ingest"
                )
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    DiscoverView()
}
