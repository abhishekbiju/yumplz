import XCTest
import SwiftData
@testable import Yumplz

@MainActor
final class RecipeSharingTests: XCTestCase {

    // Helper: recipe with one ingredient and one step
    private func makeRecipe() -> Recipe {
        let r = Recipe(title: "Test Cake")
        r.servings = 4
        r.cookTimeSeconds = 45 * 60

        let i = Ingredient(originalText: "2 cups flour", orderIndex: 0)
        r.ingredients = [i]

        let s = Step(text: "Mix the ingredients together.", orderIndex: 0)
        r.steps = [s]

        return r
    }

    // MARK: - Slice 1: plain text contains title

    func testPlainTextContainsTitle() {
        let recipe = makeRecipe()
        let text = RecipeShareFormatter.plainText(for: recipe)
        XCTAssertTrue(text.contains("Test Cake"), "Plain text must contain recipe title")
    }

    // MARK: - Slice 2: plain text contains ingredient

    func testPlainTextContainsIngredient() {
        let recipe = makeRecipe()
        let text = RecipeShareFormatter.plainText(for: recipe)
        XCTAssertTrue(
            text.contains("2 cups flour"),
            "Plain text must contain ingredient originalText"
        )
    }

    // MARK: - Slice 3: plain text contains numbered steps

    func testPlainTextContainsSteps() {
        let recipe = makeRecipe()
        let text = RecipeShareFormatter.plainText(for: recipe)
        XCTAssertTrue(text.contains("1."), "Steps must be numbered starting at 1")
        XCTAssertTrue(
            text.contains("Mix the ingredients together."),
            "Plain text must contain step text"
        )
    }

    // MARK: - Slice 4: plain text has footer

    func testPlainTextHasYumplzFooter() {
        let recipe = makeRecipe()
        let text = RecipeShareFormatter.plainText(for: recipe)
        XCTAssertTrue(text.contains("Shared from yumplz"), "Plain text must end with attribution footer")
    }

    // MARK: - Slice 5: deep link URL is valid with yumplz scheme

    func testDeepLinkURLIsValid() {
        let recipe = makeRecipe()
        let plainText = RecipeShareFormatter.plainText(for: recipe)
        let url = RecipeShareFormatter.deepLinkURL(for: plainText)
        XCTAssertNotNil(url, "deepLinkURL must not return nil")
        XCTAssertEqual(url?.scheme, "yumplz", "URL scheme must be 'yumplz'")
        XCTAssertEqual(url?.host, "import", "URL host must be 'import'")
    }

    // MARK: - Slice 6: deep link URL round-trips back to original text

    func testDeepLinkURLDecodesBackToOriginalText() {
        let recipe = makeRecipe()
        let plainText = RecipeShareFormatter.plainText(for: recipe)
        guard let url = RecipeShareFormatter.deepLinkURL(for: plainText) else {
            XCTFail("deepLinkURL returned nil")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let decoded = components?.queryItems?.first(where: { $0.name == "text" })?.value
        XCTAssertEqual(decoded, plainText, "Percent-decoded text param must equal original plain text")
    }
}
