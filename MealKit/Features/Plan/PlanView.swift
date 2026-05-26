import SwiftUI
import SwiftData

/// Plan tab — the Meal Plan calendar. Weekly horizontal-swipe view, four
/// fixed Slots per day (Breakfast/Lunch/Dinner/Snack), drag-and-drop between
/// Slots, AI Plan Generation behind paywall (Q6, Q14).
struct PlanView: View {
    @Query(sort: \PlannedMeal.date) private var plannedMeals: [PlannedMeal]

    var body: some View {
        NavigationStack {
            ScrollView {
                PlaceholderSurface(
                    title: "Plan",
                    subtitle: "Weekly view · 4 fixed Slots per day · drag-and-drop · AI Plan Generation (paid).",
                    systemImage: "calendar",
                    progress: "\(plannedMeals.count) planned meal(s) · Q14 — pending calendar UI"
                )
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    PlanView()
}
