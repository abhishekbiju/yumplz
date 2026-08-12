import SwiftUI

struct AppearanceView: View {
    @Environment(UserPreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        PurpleScreenContainer {
            List {
                Section {
                    Picker("Appearance", selection: $prefs.appearancePreference) {
                        ForEach(UserPreferencesStore.AppearancePreference.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Controls whether yumplz uses light or dark mode.")
                }
            }
            .mkInsetListStyle()
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
