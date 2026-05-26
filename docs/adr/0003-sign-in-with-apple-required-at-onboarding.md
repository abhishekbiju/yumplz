# ADR 0003 — Sign in with Apple required at onboarding

- Status: Accepted
- Date: 2026-05-24
- Amends: ADR 0001 (CloudKit for sync, no custom backend) — specifically the
  "Zero auth UX" consequence

## Context

ADR 0001 chose CloudKit private database for user data, and listed "Zero
auth UX" as a benefit: users would be identified implicitly by their iCloud
account, with no explicit sign-in step.

In the onboarding decision (Q10), we elected to **require Sign in with
Apple** during onboarding rather than make it optional. The reasoning:

- A stable, app-specific user identifier (Apple's `subject` claim) that is
  decoupled from the iCloud account — survives the user signing out of and
  back into iCloud, switching devices, or moving to a new Apple ID later.
- A real identity for support tickets ("my recipes disappeared" is easier
  to investigate when the user has an ID we can correlate logs against).
- Forward compatibility with any future server-side feature (analytics
  beyond device-only, server-rendered shares, household sharing, web
  companion) — we will already have a user identifier; we won't have to
  re-onboard the entire user base.
- StoreKit subscription receipts are tied to the Apple ID anyway; pairing
  that with an explicit Apple user identifier gives us cleaner subscription
  state recovery on device loss.

## Decision

Onboarding requires a successful Sign in with Apple before the user can
proceed past the auth screen. There is no "Skip" option. There is no
email/password alternative. There is no anonymous mode.

The Apple user identifier is stored locally and (eventually) on the
private CloudKit `User` record. It is treated as the canonical user ID for
all internal references — analytics events, error reports, subscription
state.

CloudKit private database remains the storage layer for all user data, as
per ADR 0001. The Apple identifier and the CloudKit account are
independent; we never assume they correspond, and we tolerate cases where
the user is signed into Apple ID but not iCloud (data is local-only;
notification at first launch explains sync requires iCloud).

## Consequences

### Positive

- Stable user ID for support, analytics, and forward compatibility.
- Subscription state recovery is more robust — we can tie purchase
  receipts to the user, not just the device.
- Future server-backed features (if we ever build a custom backend, see
  ADR 0001 for why we haven't) can be opt-in for existing users without
  another identity migration.

### Negative — accepted trade-offs

- **An extra step in onboarding.** The "Zero auth UX" benefit from
  ADR 0001 is forfeited. ~3 seconds added to the happy path; some
  percentage of users will bounce at the auth screen.
- **No anonymous use.** Users who decline Sign in with Apple cannot use
  the app at all. This is a deliberate trade for the benefits above.
- **Edge case: user signed into Apple ID but not iCloud.** The app works
  in local-only mode; we surface this clearly. Sync resumes if they sign
  into iCloud later.
- **Edge case: user revokes Apple ID access in Settings.** Treated as
  signed-out; relaunching prompts re-auth. Their local data is preserved
  (keyed by the Apple identifier).

### Reversal cost

Low-to-moderate. We can make Sign in with Apple optional later by
relaxing the onboarding gate; existing users would be unaffected. We
cannot easily remove the dependency from already-deployed app versions
once shipped, but new versions can soften the requirement.

## Alternatives considered

- **Optional Sign in with Apple** (the original Q10 recommendation).
  Lower friction, but no guaranteed user identifier — analytics, support,
  and forward-compat all become best-effort. Rejected in favour of having
  the identifier for everyone.
- **Email/password auth in addition.** Would require running an auth
  server, which directly contradicts ADR 0001's "no custom backend"
  decision. Rejected.
- **Sign in with Apple + Sign in with Google.** Would require a backend
  to broker the dual identity. Same rejection as above; Apple-only is
  fine for an iOS-only app.
