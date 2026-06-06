# ADR 0005 — Validate-first: defer Apple Developer Program, SIWA, CloudKit, and paywall

- Status: Accepted
- Date: 2026-05-25
- Amends: ADR 0001 (CloudKit deferred), ADR 0003 (SIWA deferred)

## Context

The app is functionally complete across all core features (issues #2–#13):
Library, Recipe import, Cook Mode, Meal Planning, Plan Generation, Grocery
List. Three features remain unimplemented (issues #14–#16):

| Issue | Feature                     | Blocker                         |
|-------|-----------------------------|---------------------------------|
| #14   | Sign in with Apple          | Apple Developer Program ($99)   |
| #15   | CloudKit sync               | Apple Developer Program ($99)   |
| #16   | Paywall (StoreKit 2)        | Apple Developer Program ($99)   |

All three blockers are the same: the paid Apple Developer Program membership,
which unlocks the `com.apple.developer.applesignin`, `iCloud`, and
`com.apple.developer.icloud-container-identifiers` entitlements, and the
ability to distribute via TestFlight and the App Store.

The question was: **enroll now ($99) to unblock these features, or validate
the core feature set first and enroll once satisfied?**

Key considerations:

- The app is intended to be **free at launch** and **zero-infrastructure-cost**
  (all LLM inference is on-device per ADR 0004). There is no recurring cost
  that accumulates while validation runs.
- Solo, single-developer validation on a personal device requires only a
  `DEBUG` build run directly from Xcode — no TestFlight, no distribution,
  no paid entitlements.
- The `DEBUG` bypass in `AuthenticationManager` (`signInAsDevUser()`) already
  provides a working development identity that is compiler-gated out of
  Release builds. Production users are never affected.
- Paying $99 before confirming the core product works as intended introduces
  financial commitment to an unvalidated assumption.
- Enrolling later (after validation) carries zero migration cost: the data
  model is already CloudKit-compatible, the SIWA flow is fully coded, and
  StoreKit 2 integration (issue #16) starts from a clean slate.

## Decision

Defer enrollment in the Apple Developer Program, and by extension the
implementation of issues #14, #15, and #16, until the core feature set
(issues #2–#13) has been validated through solo use on a personal device.

During validation:

- The app runs from Xcode in `DEBUG` mode on a personal iPhone.
- Authentication uses the `signInAsDevUser()` bypass.
- All data is local-only (SwiftData, no CloudKit sync).
- The Library is pre-populated by `DebugSeeder` on first sign-in.
- The restricted entitlements (`iCloud`, `applesignin`, APS) remain
  commented out in `project.yml`.

## Consequences

### Positive

- No financial commitment until the product is validated.
- No infrastructure overhead during validation — the app is entirely
  self-contained on one device.
- No blocking dependency: all core features are testable today.
- The codebase stays clean — issues #14–#16 will be implemented against
  a validated, stable core rather than a moving target.

### Negative — accepted trade-offs

- **Data is not durable across reinstalls.** The local SwiftData store is
  lost if the app is deleted and reinstalled. `DebugSeeder` mitigates this
  by restoring sample data automatically, but any hand-crafted recipes
  added during validation are lost.
- **Single-device only.** No sync means validation is limited to one phone.
  Cross-device behaviour (iPhone → iPad handoff, recipe sync) cannot be
  tested until issue #15 is implemented.
- **Paywall features cannot be validated end-to-end.** The Plan Generation
  paywall check (issue #16) is intentionally absent; plan generation runs
  unconditionally during validation. The gate will be added when StoreKit is
  implemented.

### Reversal cost

None. The three deferred issues (#14, #15, #16) are self-contained.
Implementing them requires:

1. Enroll in Apple Developer Program.
2. Uncomment the three entitlement blocks in `project.yml`.
3. Implement the issues in order: #14 (SIWA) → #15 (CloudKit) → #16
   (StoreKit). They have this dependency order because:
   - #15 (CloudKit) requires a real Apple user ID to key the CloudKit
     private container against; #14 must be live first.
   - #16 (StoreKit) references the User entity to gate features; #14 must
     be live first.
   - #15 and #16 are otherwise independent of each other.

No data migration is required. The validation-phase local SwiftData store
is abandoned; the CloudKit container starts empty for the first real user.

## Trigger for implementation

Implement issues #14, #15, #16 (in that order) when:

- [ ] Solo validation of issues #2–#13 is complete and the developer is
      satisfied the core product is stable.
- [ ] Apple Developer Program enrollment is confirmed.
- [ ] `project.yml` entitlements are uncommented and a provisioning
      profile is generated.

## Alternatives considered

- **Enroll immediately.** Would unblock #14–#16 now, but commits $99 before
  the core product is validated. Rejected as premature.
- **Use a free Apple Developer account with manual provisioning for SIWA.**
  Not possible — the `com.apple.developer.applesignin` entitlement is
  exclusively available to paid program members. Rejected as infeasible.
- **Ship without auth permanently (local-only app).** Rejected — ADR 0003's
  rationale for stable user IDs, support, and forward compatibility still
  holds. SIWA is deferred, not abandoned.
