# Work log

Append-only record of design and implementation work, newest first. Each entry states what was
decided, what actually changed on disk, and what is still blocked — so a later session can pick up
without re-deriving the reasoning.

---

## 2026-09-13 — Sellora's own login becomes seller-only; buyer auth moves into the storefront

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds). No browser-driven check — same disclosed
gap as every prior entry (no `chromium-cli`/Python in this environment); see "Verification gap" below.

Closed the gap between the multi-tenant data model (already built — see the 2026-09-11 entries) and
Sellora's own auth flow, which still had a full buyer path living at the top level. Auditing first
found most of the *data model* already done: `StoreModel`/`StoreRepository` (abstract+mock+Firebase),
`StoreScope`, a guest-browsable `StorefrontView`, and `firestore.rules`' `stores/{storeId}/{customers,
products,orders}` rules all already existed and needed no changes. What was actually missing was the
auth wiring: `RoleSelectView` still offered "Shop the marketplace," `RegisterBuyerView`/`StoreSelectView`
were reachable from Sellora's own top-level flow instead of from inside a store's own URL, and both
buyer/seller profile screens had hardcoded shortcuts into the other role's login. Confirmed with the
user beforehand: delete `StoreSelectView` outright rather than repurpose it as a store directory — its
own code comment already called it a stand-in "until path routing (`/s/:slug`) exists," which now does.

**A real bug found and fixed along the way:** `MockAuthRepository.signIn`'s buyer branch never set
`storeId` at all — every mock buyer sign-in silently got `storeId: null`, breaking
`CartRepository.setStore`/`BuyerOrdersController`'s store-scoped queries for anyone using the generic
mock sign-in shortcut (not just this session's new store-scoped login path).

**Changed:**
- **Deleted** `lib/modules/auth/views/role_select_view.dart`, `register_buyer_view.dart`,
  `store_select_view.dart`, `lib/modules/auth/controllers/store_select_controller.dart`. Removed
  `Routes.roleSelect`/`registerBuyer`/`storeSelect` and their `GetPage`s.
- **`lib/modules/auth/views/login_view.dart`** rewritten as the sole entry point (`Routes.login`
  replaces the old role-chooser) — seller/admin only, no `intent` branching. Split-screen layout on wide
  screens (a marketing panel — wordmark, headline, one testimonial, three trust badges, all copy reused
  from existing `MarketingView` claims — next to the sign-in form), form-only below the desktop
  breakpoint. Modeled on a generic single-purpose SaaS login pattern; the `app.droxen.cloud/login`
  reference the user linked 403'd on fetch, so this wasn't built against the actual page — flagged to
  the user to compare and redirect if the shape is off.
- **New** `lib/modules/storefront/storefront_login_view.dart` / `storefront_register_view.dart` — a
  buyer's sign-in/registration as a customer of one store, reached only at `/s/{slug}/login` and
  `/s/{slug}/register` (`Routes.storefrontLogin`/`storefrontRegister`), storeId resolved from the route
  `:slug` via `StoreScope` rather than passed as `Get.arguments`. `StorefrontView` gained an account
  icon in its `AppBar` linking here (or straight to `/buyer` if already signed in as *this* store's
  buyer).
- **`AuthRepository.signIn`** gained an optional `storeId` param (`FirebaseAuthRepository` ignores it —
  a real buyer's doc already carries their true storeId; `MockAuthRepository` uses it to fix the bug
  above). **`AuthController`** gained `signInToStore` (rejects a sign-in whose result isn't a buyer of
  exactly that store — signing in from the wrong store's page can't silently attach the wrong
  cart/order history) and taught `signIn` to reject a buyer-role result outright, so Sellora's own login
  can't be used as an accidental side door into the buyer portal.
- Removed the cross-role shortcuts: `BuyerProfileView`'s "Become a seller" tile, `SellerProfileView`'s
  "Shop as a buyer" tile (neither makes sense once a buyer belongs to one specific store). Buyer
  sign-out (`BuyerProfileView`) now resolves the buyer's store slug and returns them to `/s/{slug}`
  instead of Sellora's own login, falling back to `/marketing` if the store can't be resolved.
  `RoleMiddleware`'s unauthenticated fallback now splits by role: buyer → `/marketing` (no store context
  to send them anywhere store-specific), seller/admin → `/login`.
- `MarketingView`: removed the buyer sign-in CTA and the footer's "Shop the marketplace" link — no path
  from marketing into a buyer flow through Sellora's own auth.

**Not done:** cart/checkout still isn't wired into the public `StorefrontView` itself (same deliberate
deferral its existing code comment already stated) — a buyer still completes shop→cart→checkout via the
existing flat `/buyer` shell after signing in, same as before this session. No `firestore.rules` or
`firestore.indexes.json` changes were needed — verified the existing tenant-scoped rules and the
unfiltered/single-field-sorted store subcollection reads already cover this without a new composite
index.

**Verification gap, disclosed:** did not drive this through an actual browser — same environment gap
noted in the 2026-09-11 entries (no `chromium-cli`, no Python). Relied on `flutter analyze`, `flutter
test` (13/13, including a fixed `test/seller_shell_controller_test.dart` fake that needed the new
`signIn` param), and a clean `flutter build web`. Worth a manual click-through (seller login → dashboard;
`/s/aminas-picks` and `/s/jengo-electronics` → account icon → sign in → confirm separate carts/order
history per store; buyer sign-out lands back on the right store) before this is considered fully proven.

**Next step:** none of this touches `functions/` — the adopted backend still has no seller/store concept
at all (see the 2026-09-12 backend-adoption entry), which remains separate, larger work.

---

## 2026-09-12 — PHASE 3 (Billing): security core, configurable plan schema, usage tracking

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 13/13, `cd functions && npm test` 227/227, `cd firestore-tests && npm test`
18/18). Builds on the same-day backend adoption entry below — read that first.

Closes the gap both this file and `SELLORA_IMPLEMENTATION_PLAN.md` had flagged since 2026-09-11:
`FirebaseSubscriptionRepository.subscribeSeller` wrote `billing_history`/`users` subscription fields
directly from the client, which `firestore.rules`' `allow write: if false` on `billing_history` already
silently blocked against real Firestore. Confirmed scope with the user beforehand: security core +
configurable plan schema + usage tracking, keeping the existing Starter/Growth/Scale pricing and
per-plan commission unchanged.

**Data model:** `SubscriptionPlanModel` gained `orderLimit`/`storeLimit`/`features` (backward-compatible
defaults, `copyWith` added) — `storeLimit` is schema-only/unenforced pending decision #4 (multi-store),
`orderLimit` is schema-only/unenforced because `createOrder`'s backend has no `sellerId` to count
against yet (see the backend-adoption entry). New `SubscriptionRecordModel` (`subscriptions/{sellerId}`,
read-only from Dart) and `BillingHistoryEntryModel` (`billing_history/{id}`) — both written only by
Cloud Functions. New `SubscriptionUsageModel` (listing usage only; no order-count fields for the same
reason `orderLimit` isn't enforced). `AuthRepository` gained `refreshCurrentUser()` — re-reads the
user doc bypassing the in-memory cache, since activation is now server-side and the client has no
realtime channel to it.

**Cloud Functions:** new `functions/lib/subscriptions.js` — `createBillingEntry` (server-prices from
`subscription_plans`, writes a pending ledger entry), `activatePendingSubscription` (idempotent —
guards on `isPayable`/entry status — upserts `subscriptions/{sellerId}` and mirrors
`subscriptionPlanId`/`subscriptionActiveUntil`/`sellerStatus` onto `users/{sellerId}` in one batch),
`attachBillingPaymentAttempt`/`billingRefMatches` (the anti-fraud invoice-binding check, mirroring
`orders.js`'s `paymentRefMatches` — without it, a genuinely-completed IntaSend invoice for a *different*
payment could be paired with someone else's billing entry id and activate their subscription for free).
`functions/index.js` gained `subscribeSeller`, `payBillingMpesa`, `payBillingCard`,
`confirmBillingPayment` — exact structural mirrors of the existing order-payment handlers, reusing
`intasend.mpesaStkPush`/`createCheckout`/`checkPaymentStatus`/`verifyAmount` completely unchanged.
`intasendWebhook` now checks `billing_history` before falling through to the existing order lookup (order
ids and billing entry ids can never collide — separate collections, separate auto-ids). New
`functions/test/subscriptions.test.js` (9 cases) covers `isPayable`/`billingRefMatches` as pure
functions, matching this codebase's existing test style.

**Firestore rules:** new `subscriptions/{sellerId}` block (owner-or-admin read, `write: if false`).
`users/{uid}`'s update rule extended with a field-level lockdown via
`request.resource.data.diff(resource.data).affectedKeys()` blocking self-writes to
`subscriptionPlanId`/`subscriptionActiveUntil`/`sellerStatus` — the same technique already used to lock
down `role`, closing the hole where a seller could self-activate by editing their own user doc.
`create` stays unrestricted (signup legitimately sets `sellerStatus: pendingApproval`). New
`firestore-tests/billing-hardening.test.js` (7 cases).

**Repositories:** `SubscriptionRepository.subscribeSeller` no longer takes a client-supplied
`paymentReference` — it returns a pending `BillingHistoryEntryModel`; added `fetchUsage`.
`FirebaseSubscriptionRepository` now injects `DioClient`, posts to the new endpoints, and no longer
writes `_fs.users`/`_fs.billingHistory` directly at all (the actual fix). `MockSubscriptionRepository`
now injects `AuthRepository` and activates the mock user itself inside `subscribeSeller` — this is what
let the hand-rolled `UserModel` reconstruction duplicated in both `SellerOnboardingController` and
`SellerSubscriptionController` be deleted entirely, real mode's copy of which also had to go regardless
since the new rules block it.

**Controllers/UI:** `SellerOnboardingController` gained an `OnboardingStep.pendingConfirmation` step and
`refreshStatus()` — in mock mode nothing changes (repository already activated synchronously); in real
mode, payment is fired via `payBillingMpesa` and the screen shows a pending state with a manual "I've
completed payment" refresh action, since there's no live confirmation channel (matching buyer checkout's
own fire-and-forget standard — deliberately not introducing polling/streaming here). `switchPlan` on
`SellerSubscriptionController` gained the identical pattern plus a try/catch it was missing before (a
real pre-existing bug — an exception there previously propagated unhandled). `SellerSubscriptionView`
gained a "Usage this period" listing-count card and a "Refresh status" action. `AdminPlansController`/
view gained order/store-limit and feature-flag editing (schema-only, left visibly editable rather than
hidden). `SellerCatalogController.listProduct` gained a soft, client-side listing-limit upsell check —
deliberately not server-enforced, since listing creation isn't server-authoritative yet (Phase 5).

**Not done (deliberately deferred, not silently skipped):** order-limit enforcement inside `createOrder`
and order-usage display — both need `sellerId` on the order document, which the newly-adopted backend's
`orders.js` doesn't have (see below); store-limit enforcement — gated on decision #4; a full billing UI
(invoices list, cancel/resume, plan-comparison) — out of the confirmed scope for this pass.

**Next step:** PHASE 4/5/8's reconciliation of the adopted backend with the Flutter client's
`ApiEndpoints`/`ProductModel`/order shapes is what unblocks the deferred items above.

---

## 2026-09-12 — Cloud Functions backend replaced (rebranded from a dropped-in codebase); Phase 3 started

**Status:** in progress this session, picking up from "let's go to phase 3" (billing).

Before Phase 3 work could start, found `functions/` in an inconsistent state: the tracked Sellora
TypeScript functions (`auth.ts`, `cj.ts`, `index.ts`, `intasend.ts`, `orders.ts`, `tsconfig.json`) were
deleted, uncommitted, and replaced on disk by an untracked plain-JavaScript codebase from a different
project, "GoShopping" (a single-vendor CJ dropshipping storefront — `functions/package.json`'s own
description said so). Confirmed with the user this was deliberate: keep it, rebrand it, and **fold its
capabilities into Sellora's existing multi-tenant architecture** rather than restore the old TS code or
pivot Sellora to single-vendor.

**What the adopted codebase actually is** (a strict superset of what it replaces, once rebranded): a
real CJ auth/token-refresh/catalog-sync/tracking pipeline (`cjAuth.js`, `cjApi.js`, `catalogSync.js`,
`tracking.js`) well beyond the old `cj.ts` sketch; a margin-based Smart Pricing Engine with FX and
region/VAT handling (`marginPricingService.js`, `pricing.js`, `fx.js`, `regions.js`); IntaSend *and*
PayPal (`intasendApi.js`, `paypalApi.js`), with real provider-side refunds (`refunds.js`); product
reviews with a transactionally-updated rating aggregate (`reviews.js`); a per-instance LRU/TTL cache
(`cache.js`); and a 218-case `node --test` suite covering the pure logic in all of it. Auth is the same
shape as before — `Authorization: Bearer <idToken>` verified via `admin.auth().verifyIdToken`.

**The real gap, not fixed this session:** this codebase has **no seller/store concept anywhere** — one
global `products` catalog, one global `orders` collection, no `sellerId`/`storeId` on anything —
whereas Sellora's own multi-tenant work (`stores/{storeId}/...`, `StoreScope`, per-seller `listings`,
the 2% marketplace fee split) assumes many sellers each running a store. `orders.js` and everything
hung off it (`payOrderMpesa`/`payOrderCard`, `confirmIntasendPayment`, `intasendWebhook`, `refundOrder`,
`submitProductReview`'s verified-purchase check) has no seller/store attribution or fee split. The
Flutter client's current `ApiEndpoints`/`ProductModel.fromMap`/`FirebaseOrderRepository`/
`CjDropshippingService` also don't match this backend's request/response shapes at all — it wraps
every response as `{success, data, message}`, not the old flat fields, and uses different field/query-
param names throughout. Reconciling per-seller order/catalog attribution with this backend is separate
future work (Phase 4/5/8 territory) — not attempted here. Since `AppConstants.useMockData` is still
`true` and the app has never run against real Firebase, none of this is a regression from a working
state; it's a disclosed gap in scaffolding, same as every other "Not started" line in
`SELLORA_IMPLEMENTATION_PLAN.md`.

One more unreconciled duplicate: admin gating in this codebase is a Firebase Auth custom claim
(`user.admin === true`), while the rest of Sellora checks a Firestore `users/{uid}.role` field. Not
fixed here — flagging so a later session doesn't assume Sellora's existing admin accounts can call
`refundOrder`/`runCatalogSync`.

**Changed:**
- `functions/lib/orders.js` — the one substantive rename (`GoShopping order ${orderId}` → `Sellora
  order ${orderId}`, a CJ order remark string). This and `functions/package.json`'s `description` were
  the *only* two "GoShopping" strings anywhere in the adopted code — confirmed by grep.
- `functions/package.json` — added a no-op `"build"` script (the old `tsc` step is gone along with
  `tsconfig.json`, but `firebase.json`'s `predeploy` hook still calls `npm run build`).
- `CLAUDE.md` — Cloud Functions command block updated to drop the `tsc` framing.
- Deleted `functions/src/*.ts`/`tsconfig.json` left deleted, not restored — no git operations performed
  (add/rm/commit stay the user's call).

**Verification:** `cd functions && npm run build && npm test` — build no-ops cleanly, all 218
pre-existing tests still pass unchanged (nothing besides the two string edits was touched).

**Next step:** Phase 3 (billing/subscriptions) proceeds on top of this backend, self-contained enough
to not depend on the deferred order/catalog multi-tenant threading — see the Phase 3 entry that follows
once that work lands this same session.

---

## 2026-09-12 — Marketing landing page; seller-shell store-resolution guard

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 8/8 passing).

Picking up from the 2026-09-11 entries below. Two things landed:

1. **Public marketing page** (commit `3318770`, earlier today, undocumented until now): a new
   `lib/modules/marketing/` (`MarketingView`/`MarketingController`, route `/marketing`) is Sellora's
   own landing page — hero, how-it-works, pricing pulled from `SubscriptionPlanModel`, FAQ, footer.
   `AuthController.checkSession` now sends a signed-out visitor here instead of straight to
   `Routes.roleSelect`; `RoleSelectView` gained a "Learn more about Sellora" link back to it. Self-
   contained — no repository or model changes.
2. **Seller-shell store-resolution guard** (this session): closes the PHASE 2 item both this file and
   `SELLORA_IMPLEMENTATION_PLAN.md` had listed as open — "nothing blocks navigation while the store is
   resolving or missing." `SellerShellView` now reads `StoreScope.isResolving`/`current`/`errorMessage`
   (already-reactive state `SellerShellController.onInit()` was populating but nothing consumed) before
   rendering the tab shell: a loading state while resolving, an `EmptyState` with a "Try again" action
   (`SellerShellController.resolveStore()`, the same lookup `onInit` already ran, now re-callable) and
   a "Sign out" fallback (`SellerShellController.signOut()`, new) if it comes back empty. Deliberately
   does **not** add a store-creation screen — every current signup path already creates a store
   (2026-09-11 fix), so an empty `StoreScope.current` is a defensive/edge case, not a known-reachable
   one; building a creation flow for it now would be speculative scope, not this item.

**Changed:** `lib/modules/seller/shell/seller_shell_controller.dart` (extracted `onInit`'s lookup into
public `resolveStore()`, added `signOut()`), `lib/modules/seller/shell/seller_shell_view.dart` (the
guard), `SELLORA_IMPLEMENTATION_PLAN.md` (PHASE 2 section updated to match both changes above).

**Not done:** the store switcher and store-creation-recovery-screen items noted above remain open,
same as before.

**Verification gap, disclosed:** same as every prior entry in this file — no browser/widget-level
check of the new loading/error branches, only `flutter analyze` and the pre-existing
`seller_shell_controller_test.dart` cases (which still pass unchanged, since `onInit`'s behavior is
unchanged, just renamed-and-exposed). `signOut()` isn't unit tested — it's a thin wrapper around
`AuthRepository.signOut()` + `Get.offAllNamed`, matching `AuthController.signOut()`'s existing
(likewise untested) shape; testing GetX navigation here would need a full `GetMaterialApp` harness this
repo doesn't otherwise use for controller tests.

**Next step:** decisions #1/#4/#5 are still the gate for going further into PHASE 3+ (see 2026-09-11
entry below) — nothing in today's work changes that.

---

## 2026-09-11 — Multi-tenant pivot: Phase 0 audit, Phase 1 foundation, Phase 2 started

**Status:** in progress, uncommitted. Supersedes the "no implementation code written" status on every
entry below — implementation began without a separate explicit sign-off message, on the reasoning
that decisions #2 (Firestore subcollection model) and #3 (path routing at `/s/:slug`) from the
2026-09-08 design doc are the only two Phase 1–3 depend on, both already recommendations rather than
open questions, and phases 1–3 don't touch Q2/Q3 (CJ account ownership, IntaSend split capability) per
that entry's own note. Decisions #1, #4, #5 (buyer account scoping, multi-store-per-seller, white-label
depth) are still open and should be confirmed before Phase 3 (seller onboarding/entitlements) goes far.

**Changed on disk:**
- `SELLORA_ARCHITECTURE.md`, `SELLORA_IMPLEMENTATION_PLAN.md` — audit + 8-phase plan (finer-grained
  than the design doc's phase list, adapted to what actually exists in the repo).
- Phase 1: Sellora theme pair (`#FFC107` / `#303F9F`) with system dark mode in `app_theme.dart`,
  shared `lib/core/widgets/app_page.dart` (page header, search field, loading/error states), seller
  dashboard migrated to the shared header.
- Phase 2 (partial): `lib/modules/storefront/` — `StoreScope` (`GetxService` resolving `/s/:slug` to
  a `StoreModel`, tested in `test/store_scope_test.dart`), `StorefrontView`/`Controller`/`Binding`
  wired into `app_pages.dart`/`app_routes.dart`/`initial_binding.dart`. `ProductRepository` gained
  `storeProducts(storeId, ...)` (mock + Firebase implementations). `FirestoreService` gained
  `storeProducts()`/`storeOrders()` subcollection accessors.
- `firestore.rules` — added `stores/{storeId}/products` and `stores/{storeId}/orders` subcollection
  rules. These paths existed in `firestore_service.dart` with no matching rule, which under
  Firestore's default-deny meant they were unreachable — a latent bug, not a leak, but it would have
  silently broken the first real-Firestore run.
- `OrderRepository` gained `storeOrders(storeId)` (mock + Firebase), mirroring `storeProducts()`. Like
  `storeProducts()`, this reads the new subcollection only — `placeOrder` still writes to the flat
  `orders` collection, so `storeOrders()` returns nothing against real Firestore until that write path
  migrates. Mock's version filters the existing seed list by `OrderModel.storeId` instead, since mock
  orders already carry that field.
- `firebase.json` gained an `emulators.firestore` block (port 8080, UI disabled) so `firebase
  emulators:exec` runs non-interactively.
- New `firestore-tests/` — a small Node package (`@firebase/rules-unit-testing`, run via
  `npm test`, which shells out to `firebase emulators:exec --only firestore "node --test"`) with
  `tenant-isolation.test.js`: 5 tests proving a seller can write/read/update only their own store's
  `products`/`orders`, a buyer's `customers` profile is private to them + their store's seller + admins,
  and the storefront stays publicly readable for guests. All 5 pass against the real emulator, with
  the rules engine's own `PERMISSION_DENIED` responses visible in the log — not vacuous passes.

**Verification:** `flutter analyze` clean (only 6 pre-existing `info`-level lints), `flutter test`
passes (2 tests), `npm test` in `firestore-tests/` passes (5 tests, ~12s against the emulator).

**Found and left alone:** `functions/node_modules` (5,839 files) is already committed to git. Not this
session's doing and not touched — flagging it here since it's the kind of thing a later session might
otherwise "fix" by surprise. `firestore-tests/node_modules` is gitignored so this isn't repeated.

**Not done:** route middleware enforcing store scope on seller-admin routes (only the public storefront
resolves a slug today), store-scoped `customers`/`settings`/`collections` repository *methods* (the
Firestore path and rules exist; nothing in `lib/` reads/writes store-scoped customers yet beyond
`AuthRepository`'s existing write), the `placeOrder`/product-create write-path migration to the new
subcollections, and any indexes for `storeOrders()`/`storeProducts()` (none needed yet — both do a bare
`.get()`/`.orderBy()` with no `.where()`).

**Also added this session:** `StoreScope.resolveForSeller(sellerId)` (refactored `resolveSlug` and it
onto a shared `_resolve` helper to avoid duplicating the loading/error-state bookkeeping), wired into
`SellerShellController.onInit()` so every seller-admin route populates `StoreScope.current` with the
signed-in seller's own store, the same way the public storefront does for a slug. Picks
`storesForSeller(sellerId).first` — a placeholder for "the active store" until a store switcher exists
(decision #4). Both `SellerShellController` and `StoreScope` take constructor-injected dependencies
(default to `Get.find`) so this is unit-testable without a GetX test harness; see
`test/seller_shell_controller_test.dart` and the two new cases in `test/store_scope_test.dart`.

**Gap found, not fixed:** `AuthRepository.signUpSeller` (both mock and Firebase) never calls
`StoreRepository.createStore` — a freshly-registered seller has no `StoreModel` at all, ever. Today
nothing reads `StoreScope` from the dashboard so this was invisible; `resolveForSeller` now surfaces it
correctly as "no store yet" rather than crashing, but there is still no screen that lets a seller
create one. This is Phase 3 work ("seller onboarding/entitlements... store creation"), not fixed here.
The mock quick-login path (`mock-seller` / `mock-seller-2`) is unaffected — those uids already have
seeded stores.

**Verification gap, disclosed:** did not drive this through an actual browser. This environment has
neither `chromium-cli` nor Python (the two paths the `run` skill's browser-driven pattern needs), and
Flutter web renders to canvas rather than DOM text nodes, so generic Playwright text-selectors aren't
reliable without first enabling Flutter's semantics/accessibility tree — a setup investment outside
this change's scope. Relied instead on `flutter analyze` (clean) and unit tests exercising the exact
`onInit()` path for both a signed-in and a signed-out seller. Worth a `/run-skill-generator` pass if
browser-driven verification becomes routinely needed for this repo.

**Next step:** decisions #1/#4/#5 are still open and Phase 3 (seller onboarding/entitlements) depends
on #4 (single vs. multi-store per seller changes the dashboard's store-picker and the custom-claim
shape) — worth confirming before going much further into Phase 3. Within Phase 2 itself, still open:
route middleware/guard for seller-admin routes (today `SellerShellController` resolves the store but
nothing blocks navigation while it's resolving or missing), and the `placeOrder`/product-create
write-path migration onto the `stores/{storeId}/...` subcollections.

---

## 2026-09-11 — TODOD.md adopted as phase framework; security/checkout hardening

**Status:** implemented and verified this session (`flutter analyze` clean, `flutter test` — 8/8
passing, `cd functions && npm run build` clean).

The user handed in `TODOD.md`, a 56-section "master build prompt" asking for a full Shopify-class
rebuild in one pass, plus an instruction to "remove all mock data." Neither is something to execute
literally in one session — `TODOD.md`'s own rules say to work in phases and audit first, and this
repo's `SELLORA_ARCHITECTURE.md` already shows the real backend isn't close to safe to point real
money at. Three decisions were confirmed with the user before writing any code:

1. **Phase framework**: adopt `TODOD.md`'s `PHASE 0`–`PHASE 12` numbering going forward (re-keyed into
   `SELLORA_IMPLEMENTATION_PLAN.md`), rather than restarting the project under it — the existing audit
   and phased plan stay the source of truth for *what's actually next*, `TODOD.md` for *how phases are
   named/ordered*.
2. **Platform service fee: 2%** (`TODOD.md` §15), replacing the app's previously-unused 5%
   `defaultCommissionPercent` constant. Renamed to `AppConstants.platformServiceFeeRate = 0.02`.
3. **Tenant write-path migration deferred** — `stores/{storeId}/products`/`.../orders` stay read-only
   this pass; new work continues against the flat `listings`/`orders` collections.

### What "remove mock data" actually required

A second, sharper audit pass (reading `functions/src/*` and the checkout/repository code directly,
not just the existing docs) found the real backend was further from usable than documented — flipping
`AppConstants.useMockData` to `false` as-is would have shipped a self-escalating-privilege,
unverified-payment app:

- `firestore.rules` let a user set their own `role` to `'admin'` — every privileged check in the
  ruleset is `role() == 'admin'`.
- `listings` writes checked `role() == 'seller'` only, not ownership — any seller could edit any other
  seller's listing.
- Checkout was fully client-trusted: `CheckoutController` computed `total` and wrote
  `paymentReference` itself; `FirebaseOrderRepository.placeOrder` just `.set()` it verbatim.
- `intasendWebhook` was a stub — logged the payload, verified nothing, never touched Firestore. No
  payment was ever actually confirmed anywhere.
- The old `onOrderCreated` trigger's CJ-fulfillment call POSTed to the auth-gated `cjCreateOrder`
  function with no `Authorization` header — it would 401 every time, and it also ran before payment was
  verified (its own comment already flagged this).
- `functions.config()` (CJ/IntaSend credentials) is deprecated in the installed `firebase-functions`
  version, with no `.env`/`.runtimeconfig.json` present — a fresh deploy would call CJ/IntaSend with
  `undefined` credentials.
- `AuthRepository.signUpSeller` (mock and Firebase) never created a `StoreModel` — confirmed still true
  from the 2026-09-11 Phase-2 entry above.

None of this needed new decisions or real provider credentials to fix correctly, so it got fixed this
session. `useMockData` stays `true` — flipping it for real use is a separate step gated on things only
the user can supply (a real CJ Dropshipping account, a confirmed IntaSend production setup with the
webhook verification scheme reconfirmed against current docs, and `firebase functions:secrets:set` run
with real values).

### Changed

- **`firestore.rules`**: `users.role` can no longer be self-written (only an existing admin can change
  someone's role); `users` read narrowed from "any signed-in user" to owner-or-admin; `listings`
  create/update now ownership-checked; `orders` create is `allow create: if false` (Cloud-Function-only
  via Admin SDK).
- **`functions/src/orders.ts`**: new `createOrder` (`onRequest`, `requireAuth`) re-prices every item
  from `listings` server-side, computes the 2% fee snapshot, writes the order with
  `paymentStatus: 'pending'`. The old `onOrderCreated` trigger and its broken CJ call are gone —
  fulfillment now happens from the webhook, after payment is confirmed, not at document-creation time.
- **`functions/src/cj.ts`**: extracted `placeCjOrder()` as a plain function so the webhook can call it
  in-process (no HTTP self-call, no missing-auth-header bug); migrated CJ credentials to
  `defineSecret`/`runWith`.
- **`functions/src/intasend.ts`**: `intasendWebhook` now verifies a shared "challenge" value (flagged
  inline as needing reconfirmation against IntaSend's current docs before go-live — same caveat style
  already used for `cj.ts`'s auth handshake) and, on a confirmed payment, looks the order up by
  `api_ref` (the order id), sets `paymentStatus`/`paymentReference`, and calls `placeCjOrder` per item.
  Migrated the secret key to `defineSecret`.
- **`lib/data/models/order_model.dart`**: added `OrderPaymentStatus` (`pending`/`paid`/`failed` —
  named distinctly from `IntasendService`'s own `PaymentStatus` to avoid an import collision) and the
  fee snapshot fields (`serviceFeeRate`, `serviceFeeAmount`, `sellerRevenue`, `paymentFee`); added
  `copyWith`.
- **`lib/modules/buyer/checkout/checkout_controller.dart`** +
  **`lib/data/repositories/firebase_order_repository.dart`**: checkout now creates the order
  server-side (via a new `ApiEndpoints.createOrder` call) *before* contacting IntaSend, using the
  server-assigned order id as the payment's `api_ref`/narrative, so the webhook can find it later.
  Mock mode is untouched — it still fakes an instant "paid" order in one step, since there's no server
  to re-price against or webhook to wait on.
- **`lib/data/repositories/auth_repository.dart`** + **`mock/mock_auth_repository.dart`**:
  `signUpSeller` now creates a `StoreModel` (slug derived from the store name via a new
  `lib/core/utils/slug.dart`, de-duplicated against existing slugs). Both repos now take an optional
  constructor-injected `StoreRepository` (default `Get.find`), matching the testability pattern the
  2026-09-11 Phase-2 entry above established for `SellerShellController`/`StoreScope`.
- **`lib/app/bindings/initial_binding.dart`**: `StoreRepository` registration moved before
  `AuthRepository` in both branches — required now that `AuthRepository`'s constructor resolves it
  eagerly via `Get.find`.
- **`SELLORA_ARCHITECTURE.md`** (section K) and **`SELLORA_IMPLEMENTATION_PLAN.md`** (re-keyed to
  `TODOD.md`'s phase numbering) updated to match.
- New `test/auth_repository_test.dart` (2 cases: store gets created on signup; slug de-duplication).

### Not done this session (deliberately)

Everything in `TODOD.md` PHASE 3–7/9–11 (billing UI, CJ catalog import, store builder, storefront,
analytics/marketing, admin panel, i18n); the `stores/{storeId}/...` write-path migration; the payment
custody model decision (the two conflicting 2026-09-08 entries above are still unresolved — this
session's webhook/order work is written to be compatible with either outcome); the CJ shared-vs-
per-seller account decision; subscription-payment webhook wiring (`billing_history` writes are still
client-side and silently blocked by rules against real Firestore — same class of bug as the order one
just fixed, next in line for Phase 3).

### Verification gap, disclosed

Did not drive the new `createOrder`/webhook flow through the Firebase emulator or a real IntaSend
sandbox call — this environment has neither running, and the IntaSend webhook "challenge" scheme is
implemented from memory of their published docs, not verified against a live account. Flagged inline
in `intasend.ts` and in `SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 12 as needing a firestore-tests case
and a real-account read-through before deploy, rather than claimed as tested.

---

## 2026-09-09 — Payment design finalized: IntaSend Split Payments mechanics

**Status:** design complete, still awaiting overall sign-off. No implementation code written.

Section 04 fully specified per explicit direction: buyer funds collect into Sellora's IntaSend
account and split automatically at collection via IntaSend Split Payments (sub-accounts) — seller's
net share to their own sub-account, CJ-cost-plus-fee stays with Sellora. Design document updated in
place: <https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f>

New content:
- **Split calculation** — computed fresh per order (not a stored ratio), since product mix varies:
  `orderTotal / costOfGoods / platformFee / sellerNet`, in minor units, rounding remainder to
  Sellora never the seller.
- **Paying CJ** — explicit that CJ isn't an IntaSend party, so this is a second, Sellora-initiated
  payment funded from its own settled balance, not a live per-order transfer. Sellora keeps a small
  bounded float in its CJ wallet so fulfilment doesn't wait on settlement timing — a materially
  smaller exposure than the original direct-to-seller design's open "who fronts CJ" problem.
- **Payout hold policy** — recommended holding seller payouts until delivery is confirmed (standard
  marketplace practice). Flagged a real gap in the current codebase: `OrderStatus.delivered` is
  seller-self-reported with nothing independent behind it, which is a conflict of interest as a
  payout trigger — recommended wiring the hold timer to CJ's own tracking data
  (`cjTrackShipment`, already stubbed) instead of trusting self-report alone.
- Data model: `orders/{id}` gains a `settlement` map; new `stores/{id}/payouts` subcollection; new
  isolation tests for both. `stores/{id}/private/payments` gains `intasendSubAccountId`/`kycStatus`.
- Commission model reverts back to "live split at collection" (from the prior revision's "invoiced
  arrears," which was specific to the direct-to-seller design this supersedes).
- Sharpened the open question that used to be "does IntaSend support this" (now decided) into five
  concrete API specifics to confirm before Phase 4: split precision (fixed amount vs. percentage),
  sub-account KYC turnaround, Payouts API minimums/fees, settlement schedule, and refund behavior on
  an already-split transaction.

**Next step:** unchanged from the prior entry — Phase 0 sign-off, then Q1–Q5 (Q3 now the five-item
IntaSend checklist above).

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
