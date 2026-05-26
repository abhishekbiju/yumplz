#if DEBUG
import Foundation
import SwiftData

/// Populates the SwiftData store with a fixed set of sample recipes on first
/// launch of a DEBUG build. Idempotent — checks UserDefaults before inserting.
///
/// Called from `AuthenticationManager.signInAsDevUser()` immediately after the
/// dev user is created/restored so the library is never empty during local testing.
///
/// Recipes are chosen to exercise every feature surface:
///   - Library grid + card  (6 recipes, varied hero images not required)
///   - Recipe detail + edit (ingredients with full Structured Parses)
///   - Cook Mode            (steps with Timer Durations, Section Headers)
///   - Servings scaling     (parsedQuantity on every ingredient)
///   - Grocery aggregation  (shared ingredient names across recipes)
///   - Meal plan generation (3 cuisines, 2 dietary tag combos, 3 cook-time buckets)
enum DebugSeeder {

    private static let seededKey = "com.abhishekbiju.mealkit.debugSeeded"

    @MainActor
    static func seedIfNeeded(into context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        seed(into: context)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Force-inserts sample data regardless of the seeded flag.
    /// Useful for calling manually from the Profile screen's hidden debug menu.
    @MainActor
    static func seed(into context: ModelContext) {
        for builder in allRecipes {
            context.insert(builder())
        }
        try? context.save()
    }

    // MARK: - Recipe builders

    @MainActor private static let allRecipes: [() -> Recipe] = [
        spaghetttiCarbonara,
        chickenTikkaMasala,
        blackBeanTacos,
        overnightOats,
        greekSalad,
        salmonTeriyaki,
    ]

    // ── 1. Spaghetti Carbonara ────────────────────────────────────────────
    // Italian · ~35 min · not vegetarian (has guanciale)
    // Exercises: section headers, timer steps, dairy ingredients

    private static func spaghetttiCarbonara() -> Recipe {
        let r = Recipe(title: "Spaghetti Carbonara")
        r.summary = "A classic Roman pasta with guanciale, egg yolks, Pecorino, and black pepper — no cream allowed."
        r.cuisine = "Italian"
        r.servings = 2
        r.prepTimeSeconds = 10 * 60
        r.cookTimeSeconds = 25 * 60
        r.tags = ["pasta", "italian", "classic", "quick"]
        r.dietaryTags = []
        r.nutritionCalories = 680
        r.nutritionProteinGrams = 32
        r.nutritionCarbsGrams = 72
        r.nutritionFatGrams = 28
        r.sourceKind = .manual
        r.isFavorite = true

        let ingredients: [(String, Double?, Unit?, String?, String?, StoreCategory)] = [
            ("200g spaghetti", 200, .g, "spaghetti", nil, .pantry),
            ("100g guanciale or pancetta, diced", 100, .g, "guanciale", "diced", .meatSeafood),
            ("3 large egg yolks", 3, .piece, "egg yolks", nil, .dairyEggs),
            ("50g Pecorino Romano, finely grated", 50, .g, "Pecorino Romano", "finely grated", .dairyEggs),
            ("1 tsp freshly cracked black pepper", 1, .tsp, "black pepper", "freshly cracked", .spicesBaking),
            ("Fine sea salt, to taste", nil, .toTaste, "sea salt", nil, .spicesBaking),
        ]

        let steps: [(String, Int?, Bool)] = [
            ("Pasta & guanciale", nil, true),
            ("Bring a large pot of water to a boil. Salt generously — it should taste like the sea.", 8 * 60, false),
            ("Cook spaghetti 2 minutes less than package directions (it will finish in the sauce). Reserve 200 ml pasta water before draining.", nil, false),
            ("Meanwhile, cook guanciale in a cold, dry skillet over medium heat until rendered and crisp, about 8 minutes. Remove from heat.", 8 * 60, false),
            ("Sauce", nil, true),
            ("Whisk egg yolks, half the Pecorino, and the black pepper in a bowl until combined.", nil, false),
            ("Add drained pasta to the skillet with guanciale (off heat). Toss to coat in the fat.", nil, false),
            ("Pour egg mixture over pasta. Add pasta water a splash at a time, tossing vigorously until sauce is glossy and clings — not scrambled.", nil, false),
            ("Plate immediately, top with remaining Pecorino and extra pepper.", nil, false),
        ]

        attach(ingredients: ingredients, steps: steps, to: r)
        return r
    }

    // ── 2. Chicken Tikka Masala ───────────────────────────────────────────
    // Indian · ~55 min · not vegetarian
    // Exercises: long cook time, many spice ingredients, marinating step

    private static func chickenTikkaMasala() -> Recipe {
        let r = Recipe(title: "Chicken Tikka Masala")
        r.summary = "Charred, marinated chicken in a rich, smoky tomato-cream sauce. The quintessential British-Indian takeaway classic — made at home."
        r.cuisine = "Indian"
        r.servings = 4
        r.prepTimeSeconds = 20 * 60
        r.cookTimeSeconds = 35 * 60
        r.tags = ["chicken", "curry", "indian", "spicy"]
        r.dietaryTags = []
        r.nutritionCalories = 520
        r.nutritionProteinGrams = 45
        r.nutritionCarbsGrams = 18
        r.nutritionFatGrams = 29
        r.sourceKind = .manual

        let ingredients: [(String, Double?, Unit?, String?, String?, StoreCategory)] = [
            ("700g chicken breast, cubed", 700, .g, "chicken breast", "cubed", .meatSeafood),
            ("1 cup full-fat yoghurt", 1, .cup, "yoghurt", nil, .dairyEggs),
            ("2 tbsp tikka masala paste", 2, .tbsp, "tikka masala paste", nil, .spicesBaking),
            ("1 tsp smoked paprika", 1, .tsp, "smoked paprika", nil, .spicesBaking),
            ("2 tbsp neutral oil", 2, .tbsp, "neutral oil", nil, .pantry),
            ("1 large onion, finely diced", 1, .piece, "onion", "finely diced", .produce),
            ("4 garlic cloves, minced", 4, .clove, "garlic", "minced", .produce),
            ("1 tbsp fresh ginger, grated", 1, .tbsp, "fresh ginger", "grated", .produce),
            ("400g canned crushed tomatoes", 400, .g, "crushed tomatoes", nil, .pantry),
            ("150ml heavy cream", 150, .ml, "heavy cream", nil, .dairyEggs),
            ("1 tsp garam masala", 1, .tsp, "garam masala", nil, .spicesBaking),
            ("Salt and pepper, to taste", nil, .toTaste, "salt and pepper", nil, .spicesBaking),
        ]

        let steps: [(String, Int?, Bool)] = [
            ("Marinate", nil, true),
            ("Mix yoghurt, tikka paste, and paprika. Add chicken, coat well, and marinate at least 30 minutes (overnight is better).", 30 * 60, false),
            ("Cook chicken", nil, true),
            ("Grill or broil marinated chicken over high heat until charred in spots, about 10 minutes. Set aside.", 10 * 60, false),
            ("Sauce", nil, true),
            ("Heat oil in a wide pan. Cook onion over medium heat until golden, 10 minutes.", 10 * 60, false),
            ("Add garlic and ginger; cook 2 minutes. Add tomatoes; simmer 10 minutes.", 12 * 60, false),
            ("Stir in cream and garam masala. Add charred chicken and simmer 5 minutes until cooked through and sauce thickens.", 5 * 60, false),
            ("Season and serve over basmati rice or with naan.", nil, false),
        ]

        attach(ingredients: ingredients, steps: steps, to: r)
        return r
    }

    // ── 3. Black Bean Tacos ───────────────────────────────────────────────
    // Mexican · ~20 min · vegetarian + vegan
    // Exercises: vegan dietary tag, short cook time, Snack/Lunch slot candidate

    private static func blackBeanTacos() -> Recipe {
        let r = Recipe(title: "Black Bean Tacos")
        r.summary = "Smoky spiced black beans piled into warm corn tortillas with avocado, salsa, and lime. Ready in 20 minutes."
        r.cuisine = "Mexican"
        r.servings = 2
        r.prepTimeSeconds = 5 * 60
        r.cookTimeSeconds = 15 * 60
        r.tags = ["tacos", "beans", "vegetarian", "vegan", "quick"]
        r.dietaryTags = ["vegetarian", "vegan", "dairy-free"]
        r.nutritionCalories = 380
        r.nutritionProteinGrams = 14
        r.nutritionCarbsGrams = 58
        r.nutritionFatGrams = 12
        r.sourceKind = .manual

        let ingredients: [(String, Double?, Unit?, String?, String?, StoreCategory)] = [
            ("1 can black beans, drained and rinsed", 1, .can, "black beans", "drained and rinsed", .pantry),
            ("1 tsp cumin", 1, .tsp, "cumin", nil, .spicesBaking),
            ("½ tsp smoked paprika", 0.5, .tsp, "smoked paprika", nil, .spicesBaking),
            ("½ tsp garlic powder", 0.5, .tsp, "garlic powder", nil, .spicesBaking),
            ("1 tbsp olive oil", 1, .tbsp, "olive oil", nil, .pantry),
            ("6 small corn tortillas", 6, .piece, "corn tortillas", nil, .bakery),
            ("1 avocado, sliced", 1, .piece, "avocado", "sliced", .produce),
            ("½ cup fresh salsa", 0.5, .cup, "fresh salsa", nil, .produce),
            ("Juice of 1 lime", 1, .piece, "lime", "juiced", .produce),
            ("Fresh coriander, to serve", nil, .toTaste, "coriander", nil, .produce),
        ]

        let steps: [(String, Int?, Bool)] = [
            ("Heat olive oil in a skillet over medium heat. Add beans, cumin, paprika, and garlic powder. Cook 5 minutes, stirring occasionally, until warmed and fragrant.", 5 * 60, false),
            ("Warm tortillas directly over a gas flame or in a dry pan, 30 seconds per side.", 60, false),
            ("Mash beans lightly in the pan with the back of a fork. Season with salt and lime juice.", nil, false),
            ("Fill tortillas with bean mixture, avocado, and salsa. Top with fresh coriander.", nil, false),
        ]

        attach(ingredients: ingredients, steps: steps, to: r)
        return r
    }

    // ── 4. Overnight Oats ────────────────────────────────────────────────
    // American · 5 min + overnight · vegetarian (dairy-free option)
    // Exercises: prep-only (no cook time), Breakfast slot candidate

    private static func overnightOats() -> Recipe {
        let r = Recipe(title: "Overnight Oats")
        r.summary = "Creamy no-cook oats ready when you wake up. Endlessly customisable — top with whatever fruit or nuts you like."
        r.cuisine = "American"
        r.servings = 1
        r.prepTimeSeconds = 5 * 60
        r.cookTimeSeconds = nil   // no cooking — just soaking
        r.tags = ["breakfast", "meal-prep", "quick", "healthy"]
        r.dietaryTags = ["vegetarian"]
        r.nutritionCalories = 390
        r.nutritionProteinGrams = 18
        r.nutritionCarbsGrams = 54
        r.nutritionFatGrams = 10
        r.sourceKind = .manual

        let ingredients: [(String, Double?, Unit?, String?, String?, StoreCategory)] = [
            ("½ cup rolled oats", 0.5, .cup, "rolled oats", nil, .pantry),
            ("½ cup milk or plant-based milk", 0.5, .cup, "milk", nil, .dairyEggs),
            ("¼ cup Greek yoghurt", 0.25, .cup, "Greek yoghurt", nil, .dairyEggs),
            ("1 tbsp chia seeds", 1, .tbsp, "chia seeds", nil, .pantry),
            ("1 tbsp maple syrup or honey", 1, .tbsp, "maple syrup", nil, .pantry),
            ("½ tsp vanilla extract", 0.5, .tsp, "vanilla extract", nil, .spicesBaking),
            ("Toppings: fresh berries, banana slices, or granola", nil, .toTaste, "toppings", nil, .produce),
        ]

        let steps: [(String, Int?, Bool)] = [
            ("Combine oats, milk, yoghurt, chia seeds, maple syrup, and vanilla in a jar or container with a lid.", nil, false),
            ("Stir well. Seal and refrigerate overnight, or at least 6 hours.", 6 * 60 * 60, false),
            ("In the morning, give it a stir. Add a splash of milk if you prefer a looser consistency.", nil, false),
            ("Top with fresh fruit, granola, or nut butter. Eat cold straight from the jar.", nil, false),
        ]

        attach(ingredients: ingredients, steps: steps, to: r)
        return r
    }

    // ── 5. Greek Salad ───────────────────────────────────────────────────
    // Mediterranean · 10 min · vegetarian + gluten-free
    // Exercises: no-cook, very short, gluten-free tag, Lunch/Snack candidate

    private static func greekSalad() -> Recipe {
        let r = Recipe(title: "Greek Salad")
        r.summary = "Crisp cucumbers, tomatoes, olives, and a slab of feta in an oregano-spiked olive oil dressing. No lettuce — the Greek way."
        r.cuisine = "Mediterranean"
        r.servings = 2
        r.prepTimeSeconds = 10 * 60
        r.cookTimeSeconds = nil
        r.tags = ["salad", "greek", "no-cook", "healthy", "quick"]
        r.dietaryTags = ["vegetarian", "gluten-free"]
        r.nutritionCalories = 240
        r.nutritionProteinGrams = 8
        r.nutritionCarbsGrams = 14
        r.nutritionFatGrams = 18
        r.sourceKind = .manual

        let ingredients: [(String, Double?, Unit?, String?, String?, StoreCategory)] = [
            ("1 English cucumber, roughly chopped", 1, .piece, "cucumber", "roughly chopped", .produce),
            ("3 ripe tomatoes, cut into wedges", 3, .piece, "tomatoes", "cut into wedges", .produce),
            ("½ red onion, thinly sliced", 0.5, .piece, "red onion", "thinly sliced", .produce),
            ("100g Kalamata olives", 100, .g, "Kalamata olives", nil, .pantry),
            ("200g block feta cheese", 200, .g, "feta cheese", nil, .dairyEggs),
            ("3 tbsp extra-virgin olive oil", 3, .tbsp, "extra-virgin olive oil", nil, .pantry),
            ("1 tsp dried oregano", 1, .tsp, "dried oregano", nil, .spicesBaking),
            ("Salt and cracked pepper, to taste", nil, .toTaste, "salt and pepper", nil, .spicesBaking),
        ]

        let steps: [(String, Int?, Bool)] = [
            ("Combine cucumber, tomatoes, red onion, and olives in a large bowl.", nil, false),
            ("Drizzle with olive oil, sprinkle with oregano, salt, and pepper. Toss gently.", nil, false),
            ("Place the feta block on top (do not crumble). Finish with a final drizzle of oil and pinch of oregano.", nil, false),
            ("Serve immediately with crusty bread, or refrigerate up to 1 hour before serving.", nil, false),
        ]

        attach(ingredients: ingredients, steps: steps, to: r)
        return r
    }

    // ── 6. Salmon Teriyaki ───────────────────────────────────────────────
    // Japanese · ~25 min · gluten-free (if using tamari)
    // Exercises: fish protein variety for plan-generation variety check

    private static func salmonTeriyaki() -> Recipe {
        let r = Recipe(title: "Salmon Teriyaki")
        r.summary = "Glossy, sweet-savoury teriyaki salmon on steamed rice. A weeknight staple ready in under 30 minutes."
        r.cuisine = "Japanese"
        r.servings = 2
        r.prepTimeSeconds = 5 * 60
        r.cookTimeSeconds = 20 * 60
        r.tags = ["fish", "japanese", "healthy", "quick"]
        r.dietaryTags = ["gluten-free", "dairy-free"]
        r.nutritionCalories = 510
        r.nutritionProteinGrams = 38
        r.nutritionCarbsGrams = 46
        r.nutritionFatGrams = 18
        r.sourceKind = .manual

        let ingredients: [(String, Double?, Unit?, String?, String?, StoreCategory)] = [
            ("2 salmon fillets (about 180g each), skin on", 2, .piece, "salmon fillets", "skin on", .meatSeafood),
            ("3 tbsp soy sauce or tamari", 3, .tbsp, "soy sauce", nil, .pantry),
            ("2 tbsp mirin", 2, .tbsp, "mirin", nil, .pantry),
            ("1 tbsp sake or dry sherry", 1, .tbsp, "sake", nil, .beverages),
            ("1 tbsp brown sugar", 1, .tbsp, "brown sugar", nil, .pantry),
            ("1 tsp sesame oil", 1, .tsp, "sesame oil", nil, .pantry),
            ("1 cup short-grain white rice", 1, .cup, "short-grain rice", nil, .pantry),
            ("1 spring onion, thinly sliced", 1, .piece, "spring onion", "thinly sliced", .produce),
            ("1 tsp sesame seeds, to garnish", 1, .tsp, "sesame seeds", nil, .spicesBaking),
        ]

        let steps: [(String, Int?, Bool)] = [
            ("Rice", nil, true),
            ("Rinse rice until water runs clear. Cook in 1.5 × the volume of water: bring to a boil, reduce to lowest heat, cover, and steam 12 minutes. Remove from heat, rest 5 minutes.", 17 * 60, false),
            ("Teriyaki sauce", nil, true),
            ("Whisk soy sauce, mirin, sake, sugar, and sesame oil in a small bowl. Set aside.", nil, false),
            ("Salmon", nil, true),
            ("Heat a non-stick skillet over medium-high heat. Place salmon skin-side down. Cook 4 minutes without moving.", 4 * 60, false),
            ("Flip salmon. Pour teriyaki sauce over fillets. Cook 2–3 minutes, spooning glaze over the fish, until cooked through and sauce is sticky.", 3 * 60, false),
            ("Serve salmon over rice. Spoon remaining glaze from the pan on top. Garnish with spring onion and sesame seeds.", nil, false),
        ]

        attach(ingredients: ingredients, steps: steps, to: r)
        return r
    }

    // MARK: - Private helpers

    private static func attach(
        ingredients raw: [(String, Double?, Unit?, String?, String?, StoreCategory)],
        steps rawSteps: [(String, Int?, Bool)],
        to recipe: Recipe
    ) {
        var ingredientList: [Ingredient] = []
        for (idx, (text, qty, unit, name, prep, category)) in raw.enumerated() {
            let ing = Ingredient(originalText: text, orderIndex: idx)
            ing.parsedQuantity = qty
            ing.parsedUnit = unit
            ing.parsedName = name
            ing.parsedPrep = prep
            ing.storeCategory = category
            ing.recipe = recipe
            ingredientList.append(ing)
        }
        recipe.ingredients = ingredientList

        var stepList: [Step] = []
        for (idx, (text, timer, isHeader)) in rawSteps.enumerated() {
            let step = Step(text: text, orderIndex: idx, timerSeconds: timer, isSectionHeader: isHeader)
            step.recipe = recipe
            stepList.append(step)
        }
        recipe.steps = stepList
    }
}
#endif
