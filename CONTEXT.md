# Glossary

The canonical language of this codebase. When a term here is in tension with
how something is being discussed, this file wins — call it out and reconcile.
No implementation details, no specs, no decision rationale. Just definitions.

## User

The signed-in human using the app, identified by their Apple `subject`
claim from Sign in with Apple. Required — there is no anonymous mode. The
User identifier is independent of the iCloud account: a User can be
signed in but not iCloud-syncing, in which case their data is local-only
until they sign into iCloud. The app is single-User per install; multiple
Users on the same device is not supported in V1.

## Recipe

A cookable item in the user's Library. The atomic unit of the app. Has
canonical fields (title, summary, hero image, servings, prep/cook times,
Ingredients, Steps, tags) plus optional Nutrition and a Source. Carries a
Personal Layer of per-user state.

## Ingredient

A single line of a Recipe's ingredient list. Has an Original Text (always
present, source of truth for display) and an optional Structured Parse. The
Structured Parse, when present, enables grocery-list aggregation, Recipe
scaling, and unit conversion. Absence of a Structured Parse is normal and not
an error.

## Original Text

The verbatim string the user (or import) supplied for an Ingredient
("1 cup all-purpose flour, sifted"). Always present. Always what's shown
on the recipe screen. Editable directly by the user.

## Structured Parse

The machine-readable interpretation of an Ingredient: quantity (number),
unit (from a fixed enum plus a custom-unit escape hatch), name (the food
itself), and prep (modifier like "sifted", "diced"). Produced during import,
editable by the user, and discardable when wrong without losing the
Original Text.

## Step

A single instruction in a Recipe. Linear — no branching, no conditionals,
no sub-steps. May carry a Timer Duration. May be flagged as a Section Header.

## Timer Duration

A duration attached to a Step, auto-detected from its text during import
("bake for 25 minutes" → 1500 seconds). Surfaces in Cook Mode as a tappable
timer. User-editable.

## Section Header

A Step variant used to subdivide a Recipe ("For the dough", "For the glaze").
Not a cookable instruction; rendered as a label above the Steps that follow.

## Nutrition

A per-serving estimate of calories and macronutrients attached to a Recipe.
Always estimated, never authoritative. Surfaced to users with an "Estimated"
label.

## Source

The provenance of a Recipe — how it entered the Library. One of: URL, Photo,
Video, Manual, Pasted Text. URL and Video Sources retain the original link
for attribution and re-import.

## Personal Layer

The set of per-user state attached to a Recipe: rating, notes, favorite flag,
times cooked, last cooked date. The app is single-user per device account;
the Personal Layer is part of the Recipe, not a separate entity.

## Library

The user's full set of saved Recipes. Distinct from the Content Library
(the curated set shipped with the app) — an item from the Content Library is
not in the Library until the user explicitly saves it. When saved, a Recipe
is **copied** from the Content Library into the user's Library; subsequent
edits on either side are independent.

## Collection

A user-created named tag that groups Recipes. Flat (no nesting). A Recipe
can belong to zero or many Collections. Membership is many-to-many. The
mechanism by which the user organises their Library.

## System Collection

An always-present Collection that the user cannot delete or rename. Its
membership is computed, not stored — derived from underlying Recipe state.
The current set: **Favorites**, **Recently Added**, **Recently Cooked**,
**Needs Review**, **To Try**.

## Curated Collection

A named, editorially-grouped subset of the Content Library
("30-Minute Weeknight Dinners", "Cozy Soups"). Authored by us, not by users.
A Recipe can belong to zero or many Curated Collections. The mechanism the
app uses to feel like a magazine rather than a catalogue.

## House Recipe

A Recipe in the Content Library that we authored ourselves (rather than
ingested from an external provider). Surfaced prominently in Discover and
onboarding. Functionally identical to any other Recipe — the distinction is
provenance and editorial weight.

## Import

The act of bringing an external piece of content (URL, photo, video, pasted
text, manual entry) into the Library as a Recipe. May involve OCR,
transcription, schema parsing, and LLM normalization depending on the Source.

## Needs Review

A flag on a Recipe whose Import completed but with low confidence in one or
more fields. Persists until the user opens and edits the Recipe (or
explicitly dismisses it). Surfaces in the Library as a badge so the user
knows the system isn't sure about that Recipe.

## Cook Mode

A presentation of a Recipe optimised for hands-busy cooking: large text,
step-by-step navigation, screen-stay-awake, Timer Durations made tappable,
inline servings scaling, and the Mise en Place checklist available on
demand. Distinct from the normal Recipe view, which is optimised for
reading and editing.

## Mise en Place

The ingredient checklist surfaced inside Cook Mode. A scaled-to-current-
servings list of the Recipe's Ingredients with checkboxes; the user checks
items off as they prep them. State persists across the cook session and is
cleared on Cook Mode exit. Named after the French kitchen term for "set up
your ingredients before you cook."

## Meal Plan

The user's calendar of Planned Meals. Conceptually infinite in both
directions; the UI defaults to the current week. Past Planned Meals are
retained indefinitely (no archive concept).

## Slot

A named bucket within a day of the Meal Plan. Exactly four Slots per day,
fixed: **Breakfast**, **Lunch**, **Dinner**, **Snack**. A Slot holds zero
or more Planned Meals in user-defined order.

## Planned Meal

A single entry in a Slot. One of:

- **Recipe-backed** — references a Recipe, with `plannedServings` overriding
  the Recipe's own servings. Contributes to Grocery List aggregation.
- **Note-only** — a free-text label like "leftovers" or "takeout". No
  Recipe attached. Does not contribute to Grocery List aggregation.

A Planned Meal carries a "cooked" flag. Marking it cooked increments the
Recipe's Personal Layer `timesCooked` and updates `lastCookedAt`.

## Planned Servings

The serving count attached to a Recipe-backed Planned Meal, overridable by
the user. Drives the multiplier on every Ingredient quantity when the
Grocery List is generated:
`grocery_quantity = ingredient.qty × (plannedServings / recipe.servings)`.

## Plan Generation

The act of producing a candidate Meal Plan for a date range from a set of
constraints (cuisines, dietary, people to feed). Powered by an LLM that
draws from the user's Library and the Content Library, with variety
constraints. Always produces a draft the user reviews and accepts; never
writes Planned Meals directly without confirmation. A paid feature.

## Grocery List

A snapshot of ingredients needed for a date range of the Meal Plan, plus
any items the user adds manually. Each generation produces a new Grocery
List entity, named by its source date range. Edits to a Grocery List
(checks, deletes, quantity tweaks, manual additions) do not propagate
back to the Meal Plan or to Recipes — a Grocery List is downstream-only.

## Aggregation

The process of collapsing many Ingredient entries (across many Recipes
across many Planned Meals) into a deduplicated Grocery List. Keyed on the
Structured Parse `name` field (normalised); sums within compatible unit
families; lists separately across incompatible families. Ingredients
without a Structured Parse fall back to grouping by normalised Original
Text.

## Store Category

The shelf section an Ingredient belongs to (Produce, Dairy & Eggs, Meat &
Seafood, Pantry, Bakery, Frozen, Beverages, Spices & Baking, Other). Used
to section the Grocery List for in-store shopping flow. Assigned in priority
order: Spoonacular `aisle` if available, then LLM at Import time, then a
bundled static map, then user-overridden (stickily, per ingredient name).

## Manual Item

An entry in a Grocery List that originated from the user typing it in,
rather than from Aggregation. Flagged as such so it survives a
merge-regeneration of the list.
