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
struct YumplzApp: App {
    // Mirror the appearance key so YumplzApp can apply the color scheme
    // without owning the full UserPreferencesStore.
    @AppStorage("com.abhishekbiju.yumplz.appearancePreference")
    private var appearanceRaw: String = "system"

    private var preferredColorScheme: ColorScheme? {
        switch appearanceRaw {
        case "light": .light
        case "dark":  .dark
        default:       nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(preferredColorScheme)
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

/// True when Xcode launched this binary as a unit-test host (`TEST_HOST`).
private var isRunningUnderXCTest: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

@MainActor
private let appModelContainer: ModelContainer = {
    let schema = Schema(appSchema)

    // Unit tests inject into the yumplz process. Never touch the on-disk
    // store in that mode — XCTest relaunches the host between classes and a
    // locked/corrupt SQLite file surfaces as immediate EXC_BREAKPOINT traps.
    if isRunningUnderXCTest {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to init in-memory ModelContainer for tests: \(error)")
        }
    }

    let config = ModelConfiguration(
        "yumplz",
        schema: schema,
        isStoredInMemoryOnly: false
    )

    func deleteStoreFiles() {
        let storeURL = config.url
        let fm = FileManager.default
        try? fm.removeItem(at: storeURL)
        try? fm.removeItem(atPath: storeURL.path + "-wal")
        try? fm.removeItem(atPath: storeURL.path + "-shm")
    }

    // ── CloudKit-enabled configuration (uncomment once provisioned) ──
    // let config = ModelConfiguration(
    //     "yumplz",
    //     schema: schema,
    //     cloudKitDatabase: .private("iCloud.com.abhishekbiju.yumplz")
    // )

    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        print("⚠️ Failed to init persistent ModelContainer: \(error)")
        print("⚠️ Deleting local store and retrying once…")
        deleteStoreFiles()
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("⚠️ Retry failed; falling back to in-memory store. User data will not persist across launches.")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Failed to init in-memory ModelContainer: \(error)")
            }
        }
    }
}()
