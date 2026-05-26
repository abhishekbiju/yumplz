# ADR 0002 — Content Library sourced from Spoonacular, mirrored into CloudKit Public

- Status: Accepted
- Date: 2026-05-22

## Context

The brief insists that content is a first-class deliverable: "a library deep
enough that a paying user would find it useful from day one — not a handful
of seed items." A reasonable target is ~2,000 recipes across cuisines, meal
types, and dietary tags, growing over time.

We do not have a food editor, a test kitchen, or licensing budget for a
publisher partnership. We are a solo / very small team aiming at TestFlight.

We considered, and rejected, these sourcing strategies:

- **Hand-authored / test-kitchen.** Realistic V1 volume is 50–150 recipes
  over months of work. Unacceptable depth.
- **Public domain only** (USDA MyPlate, government nutrition orgs, older
  cookbooks past copyright). Free and legal, but dated in tone and capped
  at a few hundred recipes of inconsistent quality.
- **LLM-generated, human-vibes-checked.** Cheap and scalable but reads as
  AI-soulless at the volume the brief demands. Paying users notice the
  sameness within 30 minutes.
- **Scrape major recipe sites.** Bad-faith ToS violation; legal risk no V1
  needs.
- **Publisher partnership** (NYT Cooking, Bon Appetit, etc.). Out of
  financial reach and not interested at our scale.

## Decision

We will source the Content Library from the **Spoonacular API** as the
spine, augmented with **~50 House Recipes** authored by us for personality.

We will populate the Content Library at build/ops time using an internal
admin tool (a small CLI or Mac app) that:

1. Pulls recipes from Spoonacular,
2. Normalises them into our own `Recipe` schema (Ingredients with
   Original Text + Structured Parse, Steps with detected Timer Durations,
   Source set to the original publisher URL, attribution preserved),
3. Tags them with Cuisine / Meal Type / Dietary / Curated Collection
   membership,
4. Writes them into the **CloudKit Public Database**.

The iOS app reads the Content Library from CloudKit Public on first launch
(or via a manifest + lazy fetch), caches it in a local SQLite/SwiftData
store for offline browse and full-text search, and subscribes to record
changes so new content propagates without an app update.

When a user saves a Content Library Recipe, the app **copies** it into the
user's private Library. Edits on either side are independent. The source
link is retained for attribution.

## Consequences

### Positive

- Solves the "deep enough" problem in one move with vastly better quality
  than LLM-generated content.
- Free/cheap at V1 scale — Spoonacular's free tier covers the initial
  ingest, modest paid tier (~$30–80/mo) covers ongoing top-ups for years.
- The 50 House Recipes carry personality. They live in onboarding and
  Discover, so most users meet them first, even though the bulk of the
  corpus is API-sourced.
- CloudKit Public DB doesn't eat the user's iCloud quota and is hosted by
  Apple. No backend for us to run.
- New content propagates via CloudKit subscriptions — the app feels alive
  without app-store releases.
- Schema is ours; Spoonacular is normalised away on ingest. If we later
  swap providers (Edamam, Tasty, our own), only the admin tool changes;
  the app is unaffected.

### Negative — accepted trade-offs

- **Third-party dependency.** Spoonacular outage or pricing change affects
  our ability to add new content (but not user access to already-ingested
  content). Mitigated by mirroring rather than calling-live.
- **ToS discipline required.** Spoonacular's terms require attribution to
  the original recipe publisher and impose limits on bulk redistribution.
  Our normalised records must retain source URLs and credit. The admin
  tool must respect API rate limits.
- **Cannot ship the Content Library bundled with the app binary** without
  losing the live-update property. Trade-off accepted: first-launch
  download is the cost of being alive.
- **House Recipe authoring is still real work** (recipe writing, photos,
  testing). ~50 is a meaningful but bounded effort, sized to be doable
  before TestFlight.
- **Content quality is bounded by Spoonacular's quality.** Some recipes
  in their corpus are weaker than NYT-tier content. Mitigated by Curated
  Collections — we cherry-pick rather than expose the raw corpus.

### Reversal cost

Moderate. The app sees normalised Recipes from CloudKit Public — it doesn't
know or care where they came from. Swapping providers is an admin-tool
change. Going fully hand-authored later is a content-team decision, not a
code change.

## Alternatives considered

See **Context** above. Each was evaluated against (a) volume achievable at
V1, (b) ongoing cost, (c) quality, (d) legal exposure. Spoonacular + House
Recipes was the only option that satisfied all four for a small team.
