import SwiftUI
import SwiftData

/// Grocery tab — the current Grocery List. Sectioned by Store Category (user-
/// orderable). Multiple lists supported; most-recent is the default (Q7, Q14).
struct GroceryView: View {
    @Query(filter: #Predicate<GroceryList> { !$0.isArchived },
           sort: \GroceryList.createdAt,
           order: .reverse) private var lists: [GroceryList]

    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderSurface(
                    title: "Grocery",
                    subtitle: "Sectioned by Store Category · per-list date range · check-off · merge-or-replace on regenerate.",
                    systemImage: "cart",
                    progress: "\(lists.count) active list(s) · Q14 — pending sectioned UI"
                )
            }
            .navigationTitle("Grocery")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    GroceryView()
}
