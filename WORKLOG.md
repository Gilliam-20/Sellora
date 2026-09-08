# Work log

Append-only record of design and implementation work, newest first. Each entry states what was
decided, what actually changed on disk, and what is still blocked — so a later session can pick up
without re-deriving the reasoning.

---

## 2026-09-08 — Bug fixes + responsiveness pass (current marketplace UI)

**Status:** done. First real code changes in this repo (everything above was design-only). Scoped
to the existing marketplace-model Flutter UI — unrelated to the multi-tenant pivot below, which is
still awaiting sign-off and untouched by this pass.

### Bugs fixed

- **Buyer shell tab restore ran on every `build()`**, not once — `Get.arguments['tab']` was
  re-applied via `addPostFrameCallback` on any rebuild, silently snapping the user back to the
  checkout-handoff tab (e.g. after a MediaQuery-driven rebuild on resize). Moved into
  `BuyerShellController.onInit()`, which runs exactly once per controller lifetime.
- **Data loss on rebuild**: `TextEditingController`/`GlobalKey<FormState>` were created inline in
  `StatelessWidget.build()` in `LoginView`, `RegisterBuyerView`, `RegisterSellerView`,
  `CheckoutView`, and onboarding's `_PaymentStep` — any rebuild (a responsive `MediaQuery` read is
  exactly that trigger) would silently wipe whatever the user had typed. Converted all five to
  `StatefulWidget`s owning their controllers in `initState`/`dispose`. This was a prerequisite for
  adding responsiveness to those screens safely, not just a cleanup.
- **`MyListingsView`'s relist switch was a no-op**: `Switch.onChanged` unconditionally called
  `unlist`, so turning a paused listing back on silently did nothing. Added
  `MyListingsController.relist()` and branched on the switch's new value.
- **Admin catalog sync's "Last synced" label never updated**: the controller exposed the repo's
  plain `DateTime?` getter through an `Obx`, which has no reactive dependency on a non-Rx read — the
  sync worked, the label just never refreshed. Made `lastSyncedAt` an `Rxn<DateTime>` on the
  controller.
- **Mock-mode cold start stalled ~3s on every launch**: `MockAuthRepository.userChanges` never
  emitted until an explicit sign-in/out, so `checkSession()`'s `.first` always hit its timeout —
  directly undercutting the README's "try it in 60 seconds" claim. Now yields the current value
  immediately, matching how the Firebase-backed implementation behaves.
- **`RoleSelectView` could overflow** on a short viewport: a `Spacer()`-based `Column` with no
  scroll fallback. Fixed with a scroll view and fixed spacing rather than a flex spacer — note a
  `Spacer()` inside a `SingleChildScrollView` is a different, worse bug (unbounded-height
  `RenderFlex` crash), so the fix is spacing, not just "add scrolling."
- Plus the 5 pre-existing `flutter analyze` lint infos (missing `const`, double-quote style).

### Responsiveness

- New `lib/core/utils/responsive.dart` — breakpoints, `BuildContext` extensions (`isWide`,
  `pageHorizontalPadding`, …), `ResponsiveCenter` (caps + centers page content on wide screens),
  `centeredSliverPadding()` for `CustomScrollView` screens, `productGridDelegate()`
  (`SliverGridDelegateWithMaxCrossAxisExtent`-based, so grids grow columns with width instead of a
  hardcoded count).
- New `lib/core/widgets/adaptive_shell_scaffold.dart` — bottom nav bar below desktop width, a
  Material `NavigationRail` at/above it. All three portal shells (buyer/seller/admin) now use it,
  which also collapsed three near-duplicate shell implementations into one.
- Buyer product grid and both stat-card dashboards (seller, admin) moved from a fixed
  `crossAxisCount` to extent-based grids.
- Every list/form screen wrapped in `ResponsiveCenter` so content stops stretching edge-to-edge on
  desktop web; auth/checkout/onboarding forms capped at 440–560px and centered.
- `BottomActionBar` and the two bottom-sheet forms (seller catalog listing, subscription switch) cap
  and center their content — deliberately via a `Row`, not `Center`/`Align`: those slots (Scaffold's
  `bottomNavigationBar`, a modal bottom sheet) give bounded-but-loose height, which `Align` fills
  entirely per its own documented sizing rule; a `Row`'s cross axis always hugs its child regardless.
- `ManifestStub` and `EmptyState` got overflow/width guards so they hold up at both very narrow and
  very wide sizes.

### Verification

`flutter analyze` — 0 issues (was 5 infos). `flutter build web --release` — succeeds.

### Changed

23 view/controller files, plus 2 new files (`responsive.dart`, `adaptive_shell_scaffold.dart`) and
`common.dart`/`empty_state.dart`/`manifest_stub.dart`. Nothing under `functions/`, routing, or
Firestore rules touched — out of scope for this pass and overlapping with the pivot work below.

---

## 2026-09-08 — Payment model revision: platform collect-and-disburse

**Status:** revises decision #4 below. **No implementation code written.**

The user explicitly overrode the direct-to-seller recommendation: buyer funds must land at Sellora
first, Sellora pays CJ, keeps a service fee, and disburses the remainder to the seller. Section 04 of
the design document was rewritten to the safe version of that model rather than re-arguing against it.

**New recommendation:** collect through a licensed processor's marketplace/split-payment rails (the
IntaSend/Flutterwave/Paystack pattern behind Jumia, Uber, Airbnb, Stripe Connect) — never a bank or
M-Pesa account Sellora itself controls. The processor stays custodian of funds in transit; Sellora
only instructs the split (CJ cost / platform fee / seller payout) via API. This is lower-risk than
Sellora pooling funds itself, but not risk-free: Sellora is very likely still merchant of record for
refunds/disputes, and the processor will likely require its own aggregator/KYB onboarding.

**A genuine upside surfaced by this change:** the earlier "who fronts CJ" risk (`functions/src/cj.ts`
uses one shared platform CJ credential) is resolved differently now — Sellora holds the buyer's
payment before it owes CJ anything, so a shared CJ account is no longer credit extended to sellers,
just ordinary treasury/reconciliation work. Q2 below was downgraded accordingly.

**Commission model reverses again:** now a live split at settlement (natural, since Sellora holds the
funds) rather than the invoiced-arrears approach the direct-to-seller version required.

**New blocking question, sharper than before (Q3):** does IntaSend actually support marketplace/split
payments with sub-merchant custody? `functions/src/intasend.ts` has no notion of sub-merchants today.
If not, Flutterwave's Multi-Split Payments or Paystack's Split Payments are the named fallbacks — both
operate in Kenya and are built for exactly this.

**Changed in this repo:** the design artifact (`https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f`),
Section 04 and the open-questions Q2/Q3, updated in place. This worklog entry.

**Next step:** unchanged — still gated on Phase 0 sign-off. Q3 (processor capability) is now the
sharper blocker for Phase 4 specifically.

---

## 2026-09-08 — Multi-tenant storefront platform: design

**Status:** design complete, awaiting sign-off. **No implementation code written.**

### Goal

Evolve Sellora from a single shared marketplace into a Shopify-style platform. Each seller gets a
customizable storefront; buyers sign up as customers of *that specific store* rather than as global
Sellora accounts. Sellora keeps the seller dashboard, the shared CJ catalog, and subscription
billing. The marketplace-style shared buyer app is retired.

### Deliverable

Full design document (5 sections + open questions):
<https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f>

It covers account scoping options, the Firestore model and security rules, Flutter Web routing,
payment flow of funds, and a phased migration plan. The summary below is the decision record; the
document holds the reasoning, the comparison tables, and the isolation test checklist.

### Decisions to confirm

| # | Question | Recommendation |
|---|---|---|
| 1 | Buyer account scoping | One Firebase Auth pool + a `stores/{storeId}/customers/{uid}` profile document. **Not** Cloud Identity Platform multi-tenancy — GCIP charges per MAU from the first customer and adds tenant provisioning to the seller signup path, to buy credential isolation when MVP only needs data isolation. Accepted cost: global email uniqueness. |
| 2 | Firestore model | Store-owned data moves under `stores/{storeId}/…` **subcollections**, not flat collections with a `storeId` field — so a missed `.where()` cannot leak across tenants. Admin cross-store views become collection group queries. |
| 3 | Routing | Path routing at `/s/:slug/…` behind an injected `StoreScope`, so subdomains later are a resolver swap. Firebase Hosting cannot do wildcard subdomains — that, not effort, is why paths win for the MVP. |
| 4 | Payments | Each seller connects **their own** IntaSend account; buyer funds never touch Sellora. Sellora's revenue stays the subscription. Platform-collect-and-disburse would make Sellora a payment aggregator (CBK/NPS Act licensing, plus likely a breach of IntaSend's own terms). |
| 5 | Migration | GetX View→Controller→Repository, the `useMockData` dual-implementation split, and Meridian all survive. The buyer portal, `storefrontFeed()`, `UserRole.buyer`, and the global cart singleton do not. |

### Findings from reading the codebase

Three things surfaced during the review that are worth carrying forward regardless of the pivot:

- **`functions/src/cj.ts` uses one platform-level CJ account.** If checkout money goes directly to
  sellers, who pays CJ for the goods? A shared CJ account means Sellora fronts every merchant's
  inventory cost and invoices afterwards — unsecured credit to small sellers, a materially different
  business. Per-seller CJ accounts keep Sellora as pure software. Demo mode hides this entirely.
- **`CheckoutController` prices the cart client-side** and writes an order carrying a client-set
  `total` and `paymentReference`. Already a hole; with real merchant money behind it, it is the whole
  problem. Order creation must move into a Cloud Function that re-prices from listings.
- **`firestore.rules` allows `users` read to any signed-in user.** Today that exposes every user
  document; once buyers are tenants it would be a platform-wide customer list readable by any seller.

### Changed in this repo

- `CLAUDE.md` — new. Architecture orientation for future sessions.
- `WORKLOG.md` — new. This file.

Nothing under `lib/`, `functions/`, or `firestore.rules` was touched.

### Blocked on

1. Is there any live production data? Everything in the repo reads as pre-launch
   (`useMockData = true`, `baseFunctionsUrl` still `YOUR_FIREBASE_PROJECT`,
   `Firebase.initializeApp()` commented out). Confirming this lets the migration skip a backfill.
2. Does each seller bring their own CJ Dropshipping account, or does Sellora hold one shared account?
   Gates the payments phase and determines whether Sellora is extending credit.
3. Has IntaSend confirmed a platform/connect capability for marketplaces? Determines whether sellers
   supply raw API keys (stored in Secret Manager, never Firestore) or Sellora receives scoped
   per-merchant credentials. Ask explicitly whether funds ever transit a Sellora-owned wallet — if
   they do, the custody problem returns.
4. Will one seller ever need more than one store? Cheap now, expensive to retrofit — it changes the
   custom-claim shape and the dashboard navigation.
5. How white-label must this be at launch? If merchants need password-reset emails and sign-in pages
   carrying *their* brand, that is the trigger for Identity Platform, and it belongs in phase 1
   rather than a later migration.

### Next step

Sign off on the five decisions, answer Q1–Q5 above, then start phase 1 — `StoreModel`, `StoreScope`,
slug resolution, path URL strategy, and the `/s/:slug` route tree, all against mock data with two
seeded demo stores. Phases 1–3 need no answers to Q2 or Q3; only the payments phase is gated.
