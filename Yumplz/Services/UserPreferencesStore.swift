import SwiftUI

// MARK: - UserPreferencesStore

/// Persists user-facing preferences to a named UserDefaults suite.
/// All stored properties write through `didSet` so no explicit save calls
/// are required at the call site.
@MainActor
@Observable
final class UserPreferencesStore {

    // MARK: - UserDefaults keys

    private enum Key {
        static let dietaryDefaults      = "com.abhishekbiju.yumplz.dietaryDefaults"
        static let storeCategoryOrder   = "com.abhishekbiju.yumplz.storeCategoryOrder"
        static let mealReminderEnabled  = "com.abhishekbiju.yumplz.mealReminderEnabled"
        static let mealReminderHour     = "com.abhishekbiju.yumplz.mealReminderHour"
        static let mealReminderMinute   = "com.abhishekbiju.yumplz.mealReminderMinute"
        static let appearancePreference = "com.abhishekbiju.yumplz.appearancePreference"
    }

    // MARK: - Stored properties (all persist on didSet)

    /// Dietary tag defaults — pre-fills PlanGenerationSheet.
    var dietaryDefaults: Set<String> {
        didSet { defaults.set(Array(dietaryDefaults), forKey: Key.dietaryDefaults) }
    }

    /// Store category display order — used by GroceryView instead of StoreCategory.defaultOrder.
    var storeCategoryOrder: [StoreCategory] {
        didSet { defaults.set(storeCategoryOrder.map(\.rawValue), forKey: Key.storeCategoryOrder) }
    }

    /// Whether the daily meal reminder notification is active.
    var mealReminderEnabled: Bool {
        didSet { defaults.set(mealReminderEnabled, forKey: Key.mealReminderEnabled) }
    }

    /// Hour component (0–23) for the daily reminder; default 8.
    var mealReminderHour: Int {
        didSet { defaults.set(mealReminderHour, forKey: Key.mealReminderHour) }
    }

    /// Minute component (0–59) for the daily reminder; default 0.
    var mealReminderMinute: Int {
        didSet { defaults.set(mealReminderMinute, forKey: Key.mealReminderMinute) }
    }

    /// Light / dark / system appearance preference.
    var appearancePreference: AppearancePreference {
        didSet { defaults.set(appearancePreference.rawValue, forKey: Key.appearancePreference) }
    }

    // MARK: - Nested types

    enum AppearancePreference: String, CaseIterable {
        case system, light, dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light:  .light
            case .dark:   .dark
            }
        }

        var displayName: String {
            switch self {
            case .system: "System"
            case .light:  "Light"
            case .dark:   "Dark"
            }
        }
    }

    // MARK: - Private storage

    private let defaults: UserDefaults

    // MARK: - Init

    /// Creates a store backed by `defaults`.  Pass an isolated suite in tests
    /// so runs don't pollute each other or the real user preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // dietaryDefaults
        let savedTags = defaults.stringArray(forKey: Key.dietaryDefaults)
        dietaryDefaults = savedTags.map(Set.init) ?? []

        // storeCategoryOrder — merge saved order with any new cases added later
        if let savedRaws = defaults.stringArray(forKey: Key.storeCategoryOrder) {
            let known = savedRaws.compactMap(StoreCategory.init(rawValue:))
            let missing = StoreCategory.defaultOrder.filter { !known.contains($0) }
            storeCategoryOrder = known + missing
        } else {
            storeCategoryOrder = StoreCategory.defaultOrder
        }

        // mealReminderEnabled
        mealReminderEnabled = defaults.bool(forKey: Key.mealReminderEnabled)

        // mealReminderHour — distinguish "never set" (nil object) from 0
        if defaults.object(forKey: Key.mealReminderHour) != nil {
            mealReminderHour = defaults.integer(forKey: Key.mealReminderHour)
        } else {
            mealReminderHour = 8
        }

        // mealReminderMinute
        if defaults.object(forKey: Key.mealReminderMinute) != nil {
            mealReminderMinute = defaults.integer(forKey: Key.mealReminderMinute)
        } else {
            mealReminderMinute = 0
        }

        // appearancePreference
        if let raw = defaults.string(forKey: Key.appearancePreference),
           let pref = AppearancePreference(rawValue: raw) {
            appearancePreference = pref
        } else {
            appearancePreference = .system
        }
    }
}
