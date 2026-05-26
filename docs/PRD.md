# MealKit — Product Requirements Document

> **Status:** Draft · **Last updated:** 2026-05-25  
> **First milestone:** TestFlight beta (all features unlocked, no paywall)  
> **Second milestone:** App Store V1 (paywall enabled, paid Apple Developer account required)

---

## Problem Statement

People cook from many places — TikTok, Instagram, recipe blogs, cookbooks, handwritten cards, and their own imagination — but they have no single, reliable place to keep all of that. Existing recipe apps either require typing everything in manually, depend on cloud servers that disappear, lock recipes behind proprietary formats, or charge for features that should be standard.

Specifically, users face three compounding problems:

1. **Capture friction.** Saving a recipe from a website or a cooking video is four to seven manual steps in any existing app. Photos accumulate in the camera roll and are lost within weeks.

2. **Mealtime chaos.** Even users who save recipes never revisit them consistently, because there is no path from "saved recipes" to "what am I actually making this week" to "what do I need to buy."

3. **AI dependence.** Every app that uses AI to parse or plan requires an internet connection and charges a per-call fee, making it unpredictable and slow. If the AI servers are down, the core feature is broken.

---

## Solution

MealKit is an iOS-native recipe manager and meal planner that makes capturing, organising, cooking, and planning entirely local-first. It imports recipes from any source (URL, photo, social video, pasted text, or manual entry) using an on-device AI model that requires no internet connection after an initial one-time download. Recipes are stored, synced, and searched entirely on the user's device and iCloud — no server, no subscription just to use the core features.

The app is structured around four primary actions: **Import** (get a recipe in), **Library** (find it again), **Cook** (follow it hands-free), and **Plan** (decide what to make and buy).

---

## User Stories

### Onboarding

1. As a new user, I want to sign in with my Apple ID, so that my recipes sync across my iPhone and iPad without creating a separate account.
2. As a new user, I want to understand what the app does before signing in, so that I can decide whether it is worth the account step.
3. As a new user, I want to know that my data stays on my device and Apple's servers, so that I can trust the app with my personal meal history.
4. As a returning user, I want the app to remember that I already signed in, so that I am not prompted to sign in again on every launch.
5. As a user who revoked app access in Settings, I want to be prompted to sign in again, so that the app does not silently fail to sync.
6. As a user without iCloud enabled, I want the app to work in local-only mode, so that I can still use it and get a clear explanation of why sync is unavailable.

### Import — URL

7. As a user, I want to paste a recipe URL and have the app extract the title, ingredients, steps, and timings automatically, so that I do not have to type anything manually.
8. As a user, I want to review the extracted recipe before it is saved, so that I can catch and correct any parsing mistakes.
9. As a user, I want the app to flag an imported recipe as "Needs Review" when the AI is uncertain about any field, so that I know to check it.
10. As a user, I want the original source URL to be saved alongside the recipe, so that I can go back to the original page at any time.

### Import — Photo and Camera

11. As a user, I want to take a photo of a cookbook or handwritten recipe card and have the app read it, so that I can save physical recipes digitally without retyping them.
12. As a user, I want to import a screenshot of a recipe from my photo library, so that I can save things I previously screenshotted without re-finding the original page.
13. As a user, I want OCR text recognition to happen entirely on my device, so that my photos are never sent to a server.

### Import — Social Video

14. As a user, I want to paste the URL of a cooking video (TikTok, Instagram, YouTube) and have the app transcribe the audio and extract a recipe, so that I can save recipes I see on social media in one step.
15. As a user, I want video transcription to happen on my device, so that my viewing habits are never shared with a third party.
16. As a user, I want the app to warn me if it could not find a clear recipe in the video transcript, so that I know to add details manually.

### Import — Paste and Manual

17. As a user, I want to paste raw recipe text and have the app structure it into ingredients and steps, so that I can import from any source that lets me copy text.
18. As a user, I want to create a recipe entirely by hand, so that I can record original recipes I invented myself. *(Implementation: "Manual Entry" in the import sheet creates a blank Recipe and immediately opens it in RecipeEditView — no LLM involved.)*
19. As a user, I want to add a hero photo to any recipe I enter manually, so that my library looks consistent regardless of how a recipe was added.

### Import — Share Extension

20. As a user watching a cooking video on TikTok, Instagram, or YouTube, I want to tap Share in that app and choose MealKit, so that the video is sent directly to MealKit without me having to copy and paste a URL.
21. As a user, I want the Share Extension to accept both video files and URLs shared from any app, so that it works across all social platforms regardless of how each app exposes its share sheet.
22. As a user, I want the Share Extension to show a compact progress indicator while it queues the import, so that I know the item was received and will be processed.
23. As a user, I want the main MealKit app to open automatically after sharing, so that I can review and save the imported recipe without extra navigation steps.
24. As a user, I want a pending import badge on the Library tab if I shared something while the app was closed, so that I know there is something waiting for me to review.

### AI Model Download

20. As a first-time importer, I want to see a clear explanation of the one-time model download (size, privacy), so that I understand what I am agreeing to.
21. As a first-time importer, I want to see a download progress indicator with estimated size, so that I know the app is not frozen.
22. As a user on a slow connection, I want the download to resume if interrupted, so that I do not have to restart a 2 GB download from scratch.
23. As a user, I want the downloaded model to persist across app updates, so that I never have to re-download it after updating.
24. As a user, I want the model files to be excluded from iCloud backup, so that the 2 GB file does not consume my iCloud storage quota.

### Library — Browse

25. As a user, I want to see my recipes organised by Collection first, so that I can find recipes the same way I mentally categorise them.
26. As a user, I want System Collections (Favorites, Recently Added, Recently Cooked, Needs Review, To Try) to always be visible without any setup, so that common filters are immediately available.
27. As a user, I want to create, rename, and delete my own Collections, so that I can organise recipes the way that suits my cooking habits.
28. As a user, I want to assign a recipe to multiple Collections at once, so that a dish like "pasta carbonara" can live in both "Italian" and "Quick Weeknights".
29. As a user, I want to see a grid of recipe cards in each Collection, so that I can quickly scan by photo rather than reading titles.
30. As a user, I want to see basic recipe metadata on each card (cook time, servings, rating), so that I can decide which recipe to cook without opening it.

### Library — Search

31. As a user, I want to search across all my recipes by title, ingredient, tag, or cuisine, so that I can find a specific recipe regardless of what Collection it is in.
32. As a user, I want search results to appear instantly as I type, so that the search feels responsive and not like a round-trip to a server.
33. As a user, I want to filter search results by dietary tag, maximum cook time, or Collection, so that I can narrow down to exactly what suits today's constraints.

### Recipe Detail

34. As a user, I want to see a full recipe with a large hero photo, ingredient list, and numbered steps on a single scrollable screen, so that I can read a recipe the same way I would read a cookbook.
35. As a user, I want to scale a recipe to any number of servings by adjusting a stepper, so that ingredient quantities update automatically for the number of people I am cooking for.
36. As a user, I want to edit any field in a recipe (title, ingredients, steps, times, tags), so that I can correct import mistakes or add my own notes.
37. As a user, I want to mark a recipe as a Favorite, so that it always appears in the Favorites System Collection.
38. As a user, I want to give a recipe a 1–5 star rating, so that I can track which versions of a dish I preferred.
39. As a user, I want to add private notes to a recipe, so that I can remember what worked, what I changed, and what to do differently next time.
40. As a user, I want to see how many times I have cooked a recipe and when I last made it, so that I can rotate through my repertoire intentionally.

### Cook Mode

41. As a user cooking a recipe, I want to enter a hands-free Cook Mode with large text and one instruction visible at a time, so that I can follow the recipe without squinting at my phone.
42. As a user in Cook Mode, I want the screen to stay awake without requiring a tap, so that my phone does not lock mid-recipe.
43. As a user in Cook Mode, I want to tap a timer duration in a step to start a countdown, so that I do not have to switch to the Clock app.
44. As a user in Cook Mode, I want to run multiple overlapping timers (e.g., sauce and pasta simultaneously), so that I can manage parallel cooking tasks.
45. As a user in Cook Mode, I want to access a Mise en Place checklist of all ingredients scaled to my current serving size, so that I can confirm I have everything prepped before I start cooking.
46. As a user in Cook Mode, I want to check off Mise en Place items as I prep them, so that I do not lose track of what is measured and ready.
47. As a user in Cook Mode, I want Mise en Place state to clear when I exit Cook Mode, so that the next cook session starts clean.
48. As a user in Cook Mode, I want to swipe or tap to navigate between steps, so that I can move forward and back without leaving the current view.
49. As a user, I want the app to increment my "times cooked" counter and record "last cooked" when I finish a Cook Mode session, so that my Personal Layer stays accurate.

### Meal Planning

50. As a user, I want to see a week-view calendar of my planned meals, so that I can see my whole week at a glance.
51. As a user, I want each day to have four fixed Slots (Breakfast, Lunch, Dinner, Snack), so that I can plan at the granularity I think in naturally.
52. As a user, I want to add any saved recipe to any Slot on any day, so that I can build my meal plan incrementally.
53. As a user, I want to override the number of servings for a Planned Meal without changing the original recipe, so that cooking for 2 on Tuesday and 6 on Sunday uses the same recipe.
54. As a user, I want to add a Note-only Planned Meal (e.g., "leftovers", "takeout") to a Slot without linking a recipe, so that my plan can reflect reality even when I am not cooking.
55. As a user, I want to mark a Planned Meal as Cooked, so that the recipe's "times cooked" and "last cooked" fields update automatically.
56. As a user, I want to view past Meal Plans indefinitely, so that I can see what I cooked on any past week.

### Plan Generation (Paid Feature)

57. As a user, I want to ask the app to suggest a week's meals based on my preferences (cuisines, dietary restrictions, time budget), so that I get a starting point I can refine rather than a blank slate.
58. As a user, I want to review the AI's suggested plan before it is committed to my calendar, so that I have full control over what gets planned.
59. As a user, I want the AI to avoid repeating the same protein or cuisine on back-to-back days, so that the plan feels varied rather than monotonous.
60. As a user, I want Plan Generation to work offline after the AI model is downloaded, so that I am not blocked on a spotty connection when planning for the week.

### Grocery List

61. As a user, I want to generate a Grocery List from a date range of my Meal Plan in a single tap, so that shopping for the week takes seconds rather than manual ingredient transcription.
62. As a user, I want ingredients from all Planned Meals in the date range to be aggregated into a single list, so that "2 cups flour" from Monday's bread and "1 cup flour" from Wednesday's pancakes appears as "3 cups flour" not two separate lines.
63. As a user, I want my Grocery List to be grouped by store section (Produce, Dairy & Eggs, Meat & Seafood, etc.), so that I can walk the store efficiently without backtracking.
64. As a user, I want to check off items as I put them in my cart, so that I do not have to hold everything in my head.
65. As a user, I want to add manual items to a Grocery List (e.g., "paper towels"), so that I can consolidate my entire shopping trip in one list.
66. As a user, I want manual items to survive a list re-generation, so that I do not lose "toilet paper" just because I added a new recipe to the plan.
67. As a user, I want to see previous Grocery Lists archived and still accessible, so that I can reference what I bought for a favourite meal in the past.
68. As a user, I want edits to a Grocery List (deletions, quantity changes, check-offs) to not affect my recipes or Meal Plan, so that the shopping list is downstream-only and I can freely modify it.

### Discover — House Recipes (bundled)

69. As a new user with no imported recipes, I want to see a curated set of House Recipes from the first launch, so that the app feels useful immediately rather than empty.
70. As a user, I want to browse House Recipes by cuisine, meal type, and dietary tag, so that I can find relevant recipes without knowing what I want.
71. As a user, I want to see editorially named sections ("Quick Weeknight Dinners", "Healthy Breakfasts", "Comfort Food"), so that discovery feels like a magazine rather than a flat list.
72. As a user, I want to save any House Recipe to my personal Library with a single tap, so that adding a discovered recipe is frictionless.
73. As a user, I want my saved copy to be independent of the original House Recipe, so that I can edit it without affecting what other users see.
74. As a user, I want the hero card at the top of Discover to spotlight a featured recipe, so that every app launch has a clear suggestion.

*(Implementation note: V1 bundles ~24 House Recipes as JSON in the app bundle, loaded into an in-memory read-only store at launch. CloudKit Public Database serving is deferred to post-developer-program as per ADR 0002.)*

### Profile and Settings

75. As a user, I want to see my name, email, and the date I joined on my profile screen, so that I can confirm the identity tied to my data.
76. As a user, I want to sign out of the app on this device without losing any of my data, so that I can lend my phone to someone without exposing my recipes.
77. As a user, I want a clear explanation that signing out only affects this device, so that I do not worry about accidentally deleting my recipes.
78. As a user, I want to set my default dietary restrictions in Preferences, so that the Plan Generation sheet pre-fills with my preferences every time without me having to re-select them.
79. As a user, I want to customise the Store Category order, so that my Grocery List groups match the layout of my usual supermarket.
80. As a user, I want to enable a daily meal reminder notification at a time I choose, so that the app prompts me to check my planned meals each morning.
81. As a user, I want to toggle between system, light, and dark appearance, so that the app matches my preference regardless of my system setting.
82. As a user, I want to export all my recipes as a JSON file from the Privacy section, so that I can take my data with me if I stop using the app.
83. As a user, I want a "Delete All My Data" option in the Privacy section with a confirmation step, so that I can permanently remove everything I have stored in the app.

### Recipe Sharing Out

84. As a user, I want to share any recipe from my Library via the iOS share sheet as formatted plain text (title, ingredients, steps), so that I can send it to anyone via iMessage, email, or any other app without them needing MealKit installed.
85. As a user, I want to share a recipe as a styled image card showing the title, hero photo, and key stats, so that I can post it to Instagram Stories or send it as a visual preview.
86. As a user, I want to share a recipe via a `mealkit://` deep link that opens MealKit on another device and pre-loads the import sheet with that recipe's text, so that a friend with the app can save it with one tap.

### Paywall and Subscriptions (App Store V1)

78. As a user, I want to start a 7-day free trial of the premium tier, so that I can evaluate Plan Generation and any other paid features before committing.
79. As a user, I want to see a clear list of what is and is not included in the free tier before I am asked to pay, so that I can make an informed decision.
80. As a user, I want to restore my purchases on a new device, so that I do not have to repurchase after upgrading my phone.
81. As a beta tester using TestFlight, I want access to all features without a paywall, so that I can give feedback on everything including paid features.

### Accessibility

82. As a user who relies on Dynamic Type, I want all text in the app to scale with my system font size setting, so that the app is readable without needing a magnifier.
83. As a user who relies on VoiceOver, I want all interactive elements to have descriptive accessibility labels, so that I can navigate and use the app without looking at the screen.
84. As a user in Cook Mode with messy hands, I want all buttons to have adequate touch targets (minimum 44×44 pt), so that I can navigate without precision tapping.

---

## Implementation Decisions

### Architecture

- **Platform:** iOS 17+ native, SwiftUI, Swift 6 with strict concurrency. iPhone-only at V1.
- **Persistence:** SwiftData with a local-only `ModelConfiguration` during development. CloudKit private database integration activated once the Apple Developer Program account is provisioned (see ADR 0001).
- **No custom backend:** Zero server infrastructure. User data lives in SwiftData → CloudKit. Content Library lives in CloudKit Public Database (read-only from the app). See ADR 0001.
- **Authentication:** Sign in with Apple is the sole identity mechanism (ADR 0003). The Apple `subject` identifier is the canonical user ID. A per-device `UserDefaults` key tracks the active session independently of the CloudKit account.
- **Local AI inference:** All LLM work (recipe parsing, ingredient classification, nutrition estimation, plan generation) uses Llama 3.2 3B (Q4_K_M GGUF) via the llama.cpp XCFramework. Video transcription uses WhisperKit (CoreML port of Whisper base.en). Models are downloaded on first Import use and stored in Application Support, excluded from iCloud backup (ADR 0004).
- **Cloudflare Worker / OpenAI:** Eliminated entirely. ADR 0004 supersedes the proxy described in ADR 0001.

### Core Modules

**ModelDownloadManager**  
Single-responsibility observable class that tracks download state per `LocalModel` (LLM GGUF, Whisper). Downloads via `URLSession`, stores to `Application Support/MealKitModels/`, excludes from iCloud backup. Exposes `ensureReady(_:)` which is a no-op if the file is already on disk. States: `idle → downloading(progress) → ready | failed`.

**InferenceService**  
Observable façade over a private `LlamaActor` (Swift actor). Actor serialises all llama.cpp C API calls (single-threaded requirement). Provides `complete(system:prompt:maxNewTokens:temperature:)` and the higher-level `parseRecipe(from:)`. State: `idle → loading → ready | failed`.

**RecipeParseSchema / RecipePrompts**  
`ParsedRecipeDTO` — the Codable value type that travels from the LLM response to the SwiftData `save` function. Prompt templates for recipe extraction and four-step decomposed Plan Generation (slot enumeration → per-slot candidate ranking → variety check). All prompts use JSON schema in the prompt body and `temperature=0` for deterministic extraction.

**WhisperTranscriptionService**  
Observable class wrapping WhisperKit. Responsible for audio extraction from video URLs (via AVFoundation) and transcription. `ensureReady()` triggers the ~150 MB WhisperKit model download if needed.

**ImportService**  
Orchestrates the full import pipeline for all five source kinds: URL fetch + HTML strip → Vision OCR → WhisperKit transcription → InferenceService parse → `ParsedRecipeDTO`. The `save(_:in:)` helper maps the DTO to SwiftData models (`Recipe`, `Ingredient`, `Step`). Surfaces `ImportPhase` for UI binding.

**AuthenticationManager**  
Observable class, `@MainActor`. Manages Sign in with Apple session lifecycle: `restoreSession()` at launch (verifies ASAuthorizationAppleIDProvider credential state), `handleSignIn(result:)` for the onboarding button, `signOut()`. Persists `User` to SwiftData on first sign-in. DEBUG-only `signInAsDevUser()` bypass for development without a paid Apple Developer account.

**Content Library (future module)**  
CloudKit Public Database reader + local SQLite cache. Surfaces `Recipe` records authored by us or sourced from Spoonacular (normalised at ingest via an internal admin tool). See ADR 0002. Not yet implemented at TestFlight milestone.

### Data Model (SwiftData)

Core entities: `User`, `Recipe`, `Ingredient` (Original Text + optional Structured Parse), `Step` (with optional Timer Duration, isSectionHeader flag), `RecipeCollection` (many-to-many with Recipe), `PlannedMeal` (date + Slot + optional Recipe + optional noteText + plannedServings + isCooked), `GroceryList` (snapshot with startDate/endDate), `GroceryItem` (name, quantity, unit, StoreCategory, isChecked, isManual).

All relationships have defined inverses to satisfy CloudKit schema validation (e.g., `PlannedMeal.recipe` ↔ `Recipe.plannedMeals` with `.nullify` delete rule).

### Plan Generation decomposition (prototype decision)

Because Llama 3.2 3B struggles with a single "plan my entire week" prompt, generation is decomposed into a chain of four focused calls, each fitting within ~2 k tokens of context:
1. Enumerate (date, slot) pairs for the requested range.
2. For each slot, rank a short candidate list and pick the best fit.
3. Validate the assembled plan for variety violations.
4. Optionally swap flagged slots.

This multi-step approach keeps each individual call within reliable 3B capability (classification and ranking rather than open-ended generation).

### Glassmorphic design system

All top-level views use `.ultraThinMaterial` glass cards over a warm cream gradient background with three blurred accent blobs. Spring animations: `response: 0.35, dampingFraction: 0.72` for snappy interactions; `response: 0.5, dampingFraction: 0.8` for sheet presentations. Minimum touch targets 44×44 pt (HIG compliance). Dynamic Type throughout.

### Paywall (App Store V1, not TestFlight)

- Free tier: Import, Library, Cook Mode, Grocery List, basic Meal Plan (manual only).
- Premium tier: Plan Generation, (reserved for future: voice commands in Cook Mode, advanced nutrition tracking).
- 7-day free trial on first subscription.
- StoreKit 2 for receipt management. No paywall code ships in TestFlight builds — a `#if DEBUG` or `isTestFlight` flag unlocks all features.

---

## Testing Decisions

**What makes a good test here:** Test observable state transitions and pure data transformations — not UI layout or internal implementation details. A test should pass regardless of which prompt template produces the JSON, as long as the JSON decodes correctly to the expected domain model.

**Modules with meaningful testable interfaces:**

- **`ParsedRecipeDTO` decoding** — Given a JSON string, assert that `JSONDecoder` produces the expected field values including null-coercion. No LLM or network calls.
- **`String.extractedJSON()`** — Given a raw LLM response (possibly with preamble text before the first `{`), assert that the correct JSON substring is extracted.
- **`ImportService.save(_:in:)`** — Given a `ParsedRecipeDTO` and an in-memory `ModelContext`, assert that the correct number of `Ingredient` and `Step` entities are created with the correct field mappings (especially `orderIndex` and `storeCategory`).
- **`AuthenticationManager` state machine** — Given a mock `ModelContext` with a pre-existing `User`, assert that `restoreSession()` transitions to `.authenticated` for the dev bypass user ID without calling `ASAuthorizationAppleIDProvider`.
- **`ModelDownloadManager` state** — Assert that calling `ensureReady` when a model file already exists returns immediately in `.ready` state without starting a download task.
- **`GroceryList` aggregation** (future) — Given a set of `PlannedMeal` records with overlapping `Ingredient` names and units, assert that the aggregated `GroceryItem` list has the correct summed quantities and correct `StoreCategory` grouping.

**Prior art in the codebase:** `MealKitTests.swift` already has a test that verifies `ModelContainer` initialisation and a basic `Recipe → Ingredient` relationship insert. New tests should follow the same in-memory `ModelContainer` pattern.

---

## Out of Scope (V1)

- **Web companion.** No browser interface. CloudKit has no public REST API. See ADR 0001 reversal cost.
- **Android.** iOS-only. No cross-platform framework.
- **Social features.** No public profiles, no shareable collection URLs, no "follow a creator".
- **Multi-user on one device.** One User per install. Household sharing is a future feature.
- **Nutritional accuracy.** All nutrition values are LLM estimates, labelled "Estimated". Not suitable for medical or dietary tracking.
- **NLP / semantic search.** "Ask AI" natural language search escape hatch was removed (ADR 0004). FTS5 keyword search only.
- **Recipe scaling with unit conversion.** Scaling multiplies quantities; it does not convert "3 cups" to "710 mL" automatically.
- **Offline Content Library.** The Content Library requires a network fetch on first launch. It caches locally after.
- **Video download / caching.** The app extracts audio from a video URL but does not download or store the video itself.
- **Voice commands in Cook Mode.** Planned for a future paid-tier feature; not in V1.
- **Sign in with Google, email/password, or anonymous use.** Apple ID only (ADR 0003).
- **Localisation.** English only in V1. String extraction and `LocalizedStringKey` usage are deferred but the codebase is structured to make future localisation additive.

---

## Further Notes

**Apple Developer Program requirement.** The full feature set (CloudKit sync, Sign in with Apple) requires a paid Apple Developer Program membership ($99/year). The TestFlight milestone cannot be reached without it. The current DEBUG build runs with stripped entitlements and a synthetic dev user as a workaround.

**Model quality expectations.** Llama 3.2 3B with temperature=0 reliably extracts title, ingredient list, and numbered steps from well-structured recipe pages. It is less reliable on: heavily stylised blog HTML with large amounts of non-recipe prose, handwritten text with unusual abbreviations, and cooking videos with heavy background music obscuring speech. The "Needs Review" flag surfaces low-confidence imports for user correction.

**Content Library ingest.** The admin tool (a small Mac CLI or SwiftUI app, not yet built) pulls from the Spoonacular API, normalises records into our `Recipe` schema, and writes them to CloudKit Public Database. The app reads from CloudKit Public and caches locally. The admin tool is a separate project and not part of the iOS app build.

**Model update path.** Updating the on-device LLM version requires shipping a new app binary that points to a new model URL. The download manager checks the filename, so renaming the GGUF file (e.g., `Llama-3.2-3B-Instruct-Q4_K_M-v2.gguf`) triggers a re-download on the next `ensureReady` call.

**Naming.** "MealKit" is a placeholder. The final product name should be checked for App Store availability and trademark conflict before submission. The bundle ID `com.abhishekbiju.mealkit` must be updated in `project.yml` if the name changes.
