import SwiftUI
import SwiftData

/// App entry point. Wires up the SwiftData container with the full domain
/// model schema. CloudKit private database sync (per ADR 0001) is the target
/// configuration; for the initial scaffold we use a local-only container so
/// the app runs without an Apple Developer team configured.
///
/// To enable CloudKit, replace the simple `.modelContainer(for:)` modifier
/// with an explicit `ModelConfiguration` that sets `cloudKitDatabase`. See
/// the commented block in `appModelContainer` below.
@main
struct MealKitApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(appModelContainer)
    }
}

/// All domain entities. Order doesn't matter; SwiftData walks relationships.
private let appSchema: [any PersistentModel.Type] = [
    User.self,
    Recipe.self,
    Ingredient.self,
    Step.self,
    RecipeCollection.self,
    PlannedMeal.self,
    GroceryList.self,
    GroceryItem.self,
]

@MainActor
private let appModelContainer: ModelContainer = {
    let schema = Schema(appSchema)

    // Local-only configuration. Sufficient for development before CloudKit
    // provisioning. The container is created in-memory if disk init fails so
    // the app still launches (useful in preview / sim with stale stores).
    let config = ModelConfiguration(
        "MealKit",
        schema: schema,
        isStoredInMemoryOnly: false
    )

    // ── CloudKit-enabled configuration (uncomment once provisioned) ──
    // let config = ModelConfiguration(
    //     "MealKit",
    //     schema: schema,
    //     cloudKitDatabase: .private("iCloud.com.abhishekbiju.mealkit")
    // )

    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        // Use `print` rather than `assertionFailure` so Debug builds don't abort
        // before the in-memory fallback can run. This path is most common during
        // schema iteration when the on-disk store is stale.
        print("⚠️ Failed to init persistent ModelContainer: \(error)")
        print("⚠️ Falling back to in-memory store; user data will not persist across launches.")
        let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [fallback])
        } catch {
            // If even in-memory init fails, there's nothing useful we can do.
            fatalError("Failed to init in-memory ModelContainer: \(error)")
        }
    }
}()
