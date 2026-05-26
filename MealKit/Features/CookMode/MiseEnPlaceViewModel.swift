import Foundation
import Observation

struct MiseEnPlaceItem: Identifiable {
    let id: UUID
    let displayText: String
    var isChecked: Bool
}

@MainActor
@Observable
final class MiseEnPlaceViewModel {
    private(set) var items: [MiseEnPlaceItem]

    init(ingredients: [Ingredient], servings: Int, recipeServings: Int) {
        let scaler = ServingsScaler()
        self.items = ingredients
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { ingredient in
                MiseEnPlaceItem(
                    id: UUID(),
                    displayText: scaler.displayText(ingredient: ingredient, servings: servings, recipeServings: recipeServings),
                    isChecked: false
                )
            }
    }

    func toggle(item: MiseEnPlaceItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isChecked.toggle()
    }

    var checkedItems: [MiseEnPlaceItem] {
        items.filter { $0.isChecked }
    }

    var uncheckedItems: [MiseEnPlaceItem] {
        items.filter { !$0.isChecked }
    }
}
