import XCTest
import SwiftData
@testable import Yumplz

@MainActor
final class ManualEntryTests: XCTestCase {

    // MARK: - Slice 1: blank recipe has needsReview flag

    func testBlankRecipeHasNeedsReviewFlag() {
        let recipe = Recipe(title: "")
        recipe.sourceKind = .manual
        recipe.needsReview = true

        XCTAssertTrue(recipe.needsReview, "Manual entry recipe must have needsReview set")
        XCTAssertEqual(recipe.sourceKind, .manual)
        XCTAssertEqual(recipe.title, "")
    }

    // MARK: - Slice 2: blank recipe persisted to SwiftData

    func testBlankRecipePersistedToSwiftData() throws {
        let container = try TestModelContainer.make()
        let context = container.mainContext

        let recipe = Recipe(title: "")
        recipe.sourceKind = .manual
        recipe.needsReview = true
        context.insert(recipe)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "")
        XCTAssertTrue(fetched.first?.needsReview ?? false)
        XCTAssertEqual(fetched.first?.sourceKind, .manual)
    }
}
