import XCTest
@testable import Yumplz

@MainActor
final class UserPreferencesStoreTests: XCTestCase {

    // Each test gets its own isolated suite so tests can't interfere.
    private func makeSuite() -> UserDefaults {
        let name = "com.abhishekbiju.yumplz.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    // MARK: - Slice 1: dietary defaults round-trip

    func testDietaryDefaultsRoundTrip() {
        let suite = makeSuite()
        let store1 = UserPreferencesStore(defaults: suite)
        store1.dietaryDefaults = ["Vegetarian"]

        let store2 = UserPreferencesStore(defaults: suite)
        XCTAssertEqual(store2.dietaryDefaults, ["Vegetarian"])
    }

    // MARK: - Slice 2: store category order round-trip

    func testStoreCategoryOrderRoundTrip() {
        let suite = makeSuite()
        let store1 = UserPreferencesStore(defaults: suite)

        let reordered: [StoreCategory] = [
            .frozen, .produce, .pantry, .dairyEggs,
            .meatSeafood, .bakery, .beverages, .spicesBaking, .other,
        ]
        store1.storeCategoryOrder = reordered

        let store2 = UserPreferencesStore(defaults: suite)
        XCTAssertEqual(store2.storeCategoryOrder, reordered)
    }

    // MARK: - Slice 3: appearance preference round-trip

    func testAppearancePreferenceRoundTrip() {
        let suite = makeSuite()
        let store1 = UserPreferencesStore(defaults: suite)
        store1.appearancePreference = .dark

        let store2 = UserPreferencesStore(defaults: suite)
        XCTAssertEqual(store2.appearancePreference, .dark)
    }

    // MARK: - Slice 4: meal reminder round-trip

    func testMealReminderRoundTrip() {
        let suite = makeSuite()
        let store1 = UserPreferencesStore(defaults: suite)
        store1.mealReminderEnabled = true
        store1.mealReminderHour = 9
        store1.mealReminderMinute = 30

        let store2 = UserPreferencesStore(defaults: suite)
        XCTAssertTrue(store2.mealReminderEnabled)
        XCTAssertEqual(store2.mealReminderHour, 9)
        XCTAssertEqual(store2.mealReminderMinute, 30)
    }

    // MARK: - Slice 5: default order matches system default

    func testDefaultStoreCategoryOrderMatchesSystemDefault() {
        let suite = makeSuite()
        let store = UserPreferencesStore(defaults: suite)
        XCTAssertEqual(store.storeCategoryOrder, StoreCategory.defaultOrder)
    }
}
