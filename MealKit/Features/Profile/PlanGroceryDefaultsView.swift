import SwiftUI

struct PlanGroceryDefaultsView: View {
    @Environment(UserPreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        List {
            Section {
                ForEach(prefs.storeCategoryOrder) { category in
                    Text(category.displayName)
                }
                .onMove { from, to in
                    prefs.storeCategoryOrder.move(fromOffsets: from, toOffset: to)
                }
            } footer: {
                Text("Drag to reorder how categories appear in your grocery list.")
            }

            Section {
                Button("Reset to default") {
                    prefs.storeCategoryOrder = StoreCategory.defaultOrder
                }
                .foregroundStyle(.tint)
            }
        }
        .navigationTitle("Store Category Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
    }
}
