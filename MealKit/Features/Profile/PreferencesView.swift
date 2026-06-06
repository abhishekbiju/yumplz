import SwiftUI

struct PreferencesView: View {
    @Environment(UserPreferencesStore.self) private var prefs

    private let allTags = [
        "Vegetarian", "Vegan", "Gluten-Free",
        "Dairy-Free", "Nut-Free", "Halal", "Kosher",
    ]

    var body: some View {
        PurpleScreenContainer {
            List {
            Section {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        if prefs.dietaryDefaults.contains(tag) {
                            prefs.dietaryDefaults.remove(tag)
                        } else {
                            prefs.dietaryDefaults.insert(tag)
                        }
                    } label: {
                        HStack {
                            Text(tag)
                                .foregroundStyle(.primary)
                            Spacer()
                            if prefs.dietaryDefaults.contains(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Default dietary restrictions")
            } footer: {
                Text("These are pre-selected when you generate a new meal plan.")
            }
            }
            .mkInsetListStyle()
        }
        .navigationTitle("Dietary Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
