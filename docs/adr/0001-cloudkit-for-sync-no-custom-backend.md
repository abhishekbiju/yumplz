# ADR 0001 — CloudKit for sync, no custom backend (for V1)

- Status: Accepted
- Date: 2026-05-22

## Context

We are building an iOS-first clone of ReciMe (recipe import, collections, meal
planning, grocery list, cook mode). The brief targets TestFlight as the first
launch milestone and demands the app "feel like a credible paid app, not a thin
demo." It does not require a web companion, a social feed, or public profiles.

The app needs:

- Per-user persistence of recipes, collections, meal plans, grocery lists,
  cook-mode state, settings.
- Sync across a user's iPhone and (later) iPad.
- A path to ship V1 quickly without standing up auth, a database, an ops
  rotation, or a DPA process.

The competitor (ReciMe) runs a custom backend, which enables their web
companion and shareable public collections. We have explicitly chosen to defer
those features.

## Decision

We will use **CloudKit private database** (via SwiftData's CloudKit
integration) as the only persistence and sync mechanism for user data in V1.
We will not run our own backend for user data.

~~The single piece of server infrastructure we will operate is a thin
**Cloudflare Worker** that proxies recipe-import calls to OpenAI (to hide the
API key, rate-limit per device, and cache parsed results by source-URL hash).
That Worker is stateless w.r.t. users — it does not store recipes, accounts,
or PII.~~

> **Superseded by ADR 0004 (2026-05-25).** The Cloudflare Worker and all
> OpenAI API calls are eliminated. All inference runs on-device via llama.cpp
> (Llama 3.2 3B) and WhisperKit. The app now operates with **zero server
> infrastructure** of any kind.

## Consequences

### Positive

- Zero auth UX. Users are identified by their iCloud account; if they're
  signed into iCloud, sync just works. This removes an entire onboarding step
  and a whole class of support tickets.
- Zero servers to operate for user data. No database, no migrations, no
  on-call, no GDPR DPA, no SOC2 conversations.
- Free at our scale. CloudKit's free tier is generous and scales with user
  count (Apple covers it).
- Faster time to TestFlight by an estimated 4–8 weeks of work.

### Negative — accepted trade-offs

- **No web companion, ever, without migrating off CloudKit.** CloudKit has no
  public web/REST API beyond CloudKit JS (which still requires Apple ID
  sign-in). If we later want a real web app, this is a months-long migration
  to Postgres + a custom backend.
- **No anonymous sync.** If a user is signed out of iCloud, their data is
  local-only. We will surface this clearly in onboarding. Empirically the
  overwhelming majority of iPhone users are signed in, so this is acceptable.
- **No public sharing or social features.** No public profiles, no shareable
  collection URLs, no "follow a creator." Sharing is limited to share-sheet
  exports (PDF, text, single-recipe deep links the recipient must re-import).
- **No server-side analytics on user content.** We cannot query "what are
  the most-saved recipes this week" — Apple intentionally prevents it. We
  will rely on event analytics (PostHog/Mixpanel) for product metrics only.
- **CloudKit schema changes are awkward.** Adding fields is fine; renaming
  or restructuring requires a deploy of the CloudKit schema and a migration
  inside the app. We will treat the SwiftData model as append-only after V1
  ships.

### Reversal cost

High. A future migration to a custom backend involves: standing up auth,
choosing a database, writing a sync engine, building an export path from
CloudKit, and a careful cutover for existing users. Estimate 2–4 months of
focused work. We are accepting this debt knowingly in exchange for V1 speed.

## Alternatives considered

- **Supabase / Firebase.** Real backend, auth out of the box, web support.
  Rejected for V1 because we don't need web or social features, and the
  ongoing cost (auth UX, account recovery, DPA, server ops) is not worth it
  this early.
- **Custom backend (Node/Postgres or similar).** Maximum flexibility, highest
  cost. Rejected for the same reasons, more so.
- **Local-only (no sync).** Cheapest of all. Rejected because cross-device
  sync is table-stakes for a "credible paid app" in 2026 — users save a
  recipe on their phone and expect it on their iPad in the kitchen.
