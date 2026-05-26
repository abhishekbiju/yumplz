# MealKit (placeholder name)

iOS recipe importer + meal planner + cook companion. Native SwiftUI + SwiftData
+ CloudKit. iPhone-only at V1, TestFlight-bound.

The product brief, glossary, and architectural decisions live in:

- `CONTEXT.md` — domain glossary (single source of truth for terminology)
- `docs/adr/0001-cloudkit-for-sync-no-custom-backend.md`
- `docs/adr/0002-content-library-via-spoonacular-mirrored-into-cloudkit-public.md`
- `docs/adr/0003-sign-in-with-apple-required-at-onboarding.md`

`MealKit` is a working placeholder name. A real name will be chosen pre-launch
after App Store and trademark availability checks. Rename via global
find-replace on `MealKit` when committing to a real name.

## Prerequisites

- **macOS** with **Xcode 16+** (install from the Mac App Store; ~10 GB)
- **Homebrew** (already present in the dev environment)
- **xcodegen** (installed via `brew install xcodegen`)

After installing Xcode, run once:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## Setup

Generate the Xcode project from `project.yml`:

```bash
xcodegen generate
```

Open the project in Xcode:

```bash
open MealKit.xcodeproj
```

In Xcode, **Signing & Capabilities → All → set Team** to your Apple Developer
team. The bundle identifier prefix is `com.example` — change it in
`project.yml` and regenerate.

## Build from CLI

```bash
xcodebuild \
  -project MealKit.xcodeproj \
  -scheme MealKit \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Project layout

```
MealKit/
├── App/                    — App entry point, root view, tab structure
├── Models/                 — SwiftData entities (one per glossary term)
├── Features/
│   ├── Discover/
│   ├── Library/
│   ├── Plan/
│   ├── Grocery/
│   └── Profile/
└── Resources/              — Assets, fonts, seed content (later)

MealKitTests/               — XCTest target

docs/                       — ADRs and design history
CONTEXT.md                  — Domain glossary
project.yml                 — xcodegen project spec (the .xcodeproj is ignored)
```

## Regenerating the project

Any time you add a Swift file, run:

```bash
xcodegen generate
```

The `.xcodeproj` is **not** checked in. `project.yml` is the source of truth.

## Status

- [x] Project scaffolded
- [x] SwiftData models for the full domain
- [x] App skeleton with 5-tab bottom bar and placeholder views
- [ ] Sign in with Apple onboarding flow
- [ ] Recipe import pipeline (URL → JSON-LD → LLM fallback)
- [ ] Recipe detail screen
- [ ] Library screen (Collections-first)
- [ ] Cook Mode
- [ ] Meal Plan
- [ ] Grocery List
- [ ] Discover (Content Library + Curated Collections)
- [ ] Paywall + StoreKit 2 integration
- [ ] Spoonacular admin ingest tool (separate CLI)
