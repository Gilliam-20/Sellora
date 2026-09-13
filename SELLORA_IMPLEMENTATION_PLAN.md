# Sellora Implementation Plan

## Guardrails

Preserve the current GetX/repository split, mock mode, and working portals while a replacement is
built. Each repository contract change includes mock and Firebase implementations. No payment,
fulfillment, fee, or Firestore-rule migration ships without tests and Firebase Emulator verification.

## Phase framework

As of 2026-09-11 this plan re-keys to `TODOD.md`'s `PHASE 0`–`PHASE 12` numbering (its 56-section
"master build prompt") rather than this document's own earlier numbering — see `WORKLOG.md`
(2026-09-11) for why. `TODOD.md` itself is treated as an aspirational reference, not a literal spec to
execute section-by-section in one pass; each phase below still only does what the codebase audit
(`SELLORA_ARCHITECTURE.md`) shows is actually next.

## Decisions on record

- Platform service fee: **2%** of order subtotal (TODOD §15), snapshotted per order
  (`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue`/`paymentFee` on `OrderModel`), never
  shipping/tax unless configured, never retroactively changed on historical orders.
- The `listings`/`orders` flat collections → `stores/{storeId}/products` / `stores/{storeId}/orders`
  write-path migration is **deferred** — today those subcollections are read-only and always empty.
  Don't build new features against them until that migration lands.
- Payment custody model (platform collect-and-disburse vs. each seller connects their own IntaSend
  account) is still **open** — see the two conflicting 2026-09-08 `WORKLOG.md` entries. Work done so
  far (order creation, webhook confirmation) is written to be compatible with either: it confirms *a*
  payment against *an* order without assuming who the payout ultimately goes to.
- CJ Dropshipping account model (shared platform credential vs. per-seller) is still **open** —
  unchanged, still one platform credential in `functions/src/cj.ts`.

## PHASE 0 — Audit: done

`SELLORA_ARCHITECTURE.md` (sections A–P, dated 2026-09-11), refreshed same day with the sharper
findings from a second pass over `functions/src/*` and the checkout/repository code (section K).

## PHASE 1 — Foundation: done

The #FFC107 / #303F9F Sellora theme pair, system dark mode, shared page/header/search/loading/error
primitives, unified breakpoints, and a documented route/component convention. The responsive shell and
Meridian signature card are retained. Exit criteria met: `flutter analyze` clean, web build passes.

## PHASE 2 — Auth + seller onboarding: in progress

Done: `StoreScope` resolving both `/s/:slug` and a signed-in seller's own store
(`resolveForSeller`), wired into `SellerShellController.onInit()`; `storeProducts()`/`storeOrders()`
read methods (mock + Firebase) with matching Firestore rules; `firestore-tests/` emulator suite proving
tenant isolation on products/orders/customers; **`AuthRepository.signUpSeller` now creates a
`StoreModel` for every new seller** (mock + Firebase, 2026-09-11 — previously a seller had no store at
all after signing up); a public marketing/landing page (`lib/modules/marketing/`) is now the entry
point for a signed-out visitor (`AuthController.checkSession` → `Routes.marketing`, 2026-09-12); a
loading/error guard now sits in front of the seller shell so it can no longer render fully-interactive
tabs while `StoreScope` is still resolving or failed to find a store (`SellerShellView`, 2026-09-12 —
see `WORKLOG.md`).

Still open: a store switcher for multi-store sellers (today `resolveForSeller` just picks
`storesForSeller(sellerId).first`) — gated on decision #4; onboarding completion state and plan
selection (folds into PHASE 3); still no screen that lets a seller *create* a store if the guard's
"you haven't created a store yet" branch is ever hit for a real account (today it can only offer retry
and sign-out) — every current signup path already creates one, so this is a defensive path, not a
known-reachable gap.

## PHASE 3 — Billing: security core + plan schema + usage tracking done, richer UI not started

Done (2026-09-12, see `WORKLOG.md`): `subscribeSeller` moved fully server-side (`functions/lib/
subscriptions.js` + three new `payBillingMpesa`/`payBillingCard`/`confirmBillingPayment` endpoints,
mirroring the order-payment handlers exactly); `billing_history`/`subscriptions/{sellerId}` are now
Cloud-Function-only end to end (the client-write bug this phase used to be blocked on is fixed —
`FirebaseSubscriptionRepository` no longer touches either collection directly); `users/{uid}`'s
subscription fields are field-lockdown-protected the same way `role` already was. `SubscriptionPlanModel`
gained `orderLimit`/`storeLimit`/`features` (configurable, admin-editable) — kept existing
Starter/Growth/Scale naming/pricing/commission unchanged per user decision, not renamed to TODOD §16's
Starter/Growth/Pro numbering. Listing usage is tracked and displayed; the hand-rolled `UserModel`
reconstruction duplicated across the onboarding and subscription controllers is gone.

Not started: order-limit enforcement and order-usage display (both need `sellerId` on the order
document, which the PHASE 4 backend swap below doesn't have yet — this is the same gap, not a new one);
store-limit enforcement (gated on decision #4); cancel/resume, billing-history/invoices UI, a real
plan-comparison screen — none of this was in the confirmed scope for the 2026-09-12 pass.

## PHASE 4 — Catalog, pricing, and CJ import

Confirm the CJ account/API contract, add a supplier adapter, shipping quote contract, integer-minor-
unit `Money` type, configurable pricing rules, import drafts. Not started as app-facing work, but
`functions/`'s backend for this phase changed underneath it 2026-09-12 (see `WORKLOG.md`): a real CJ
auth/catalog-sync/tracking pipeline and a margin-based pricing engine (FX, region/VAT) now exist
server-side, adopted from a rebranded external codebase — well past the old `cj.ts` sketch. Still
unstarted: reconciling any of it with the Flutter client (`ApiEndpoints`, `ProductModel.fromMap`,
`CjDropshippingService` all expect different request/response shapes than this backend returns) and
deciding how a shared CJ catalog (`products`/`categories`, no seller scoping) maps onto per-seller
`listings` at import time.

## PHASE 5 — Seller product management

Store-scoped products/variants/inventory/collections/SEO, server-authorized write paths, paginated
query contracts, responsive list/table/grid states, bulk operations. Not started — blocked behind the
deferred `stores/{storeId}/products` write-path migration above.

## PHASE 6 — Store builder

Theme/section/block/setting models, renderer/preview/publish flow. Not started.

## PHASE 7 — Customer storefront

Replace the shared buyer feed with `/s/:slug` storefront pages, store-bound carts, customer profiles
beneath that store. Not started.

## PHASE 8 — Payments + orders: slice done, rest not started

Done (2026-09-11): order creation moved server-side — a new `createOrder` Cloud Function re-prices
every item from its `listings` doc (never trusting a client-supplied total/seller), snapshots the 2%
fee fields, and writes the order; `orders/{orderId}` create is `allow create: if false` in rules, so no
client path can write an order doc directly anymore. `intasendWebhook` now verifies a shared
"challenge" value (needs reconfirming against IntaSend's current docs before go-live) and, on a
confirmed payment, sets the order's `paymentStatus` and calls CJ fulfillment
(`placeCjOrder`, extracted from `cj.ts`'s old HTTP-only `cjCreateOrder` handler — the previous
`onOrderCreated` trigger's fulfillment call was broken, missing the auth header its own target
endpoint required).

Not started: payment provider abstraction (still IntaSend-only), refunds, the full fulfillment state
machine, multi-seller-cart splitting (still rejected rather than handled), subscription-payment webhook
wiring (PHASE 3's job).

**2026-09-12 update:** the `functions/` backing this phase was replaced (see `WORKLOG.md`) with a
rebranded external codebase that actually *does* have PayPal support and real provider-side refunds —
but it's single-vendor (no `sellerId`/`storeId`, no marketplace fee split anywhere in `orders.js`), so
none of "not started" above is actually closed by it. The old `createOrder`/`intasendWebhook`
description above (server-priced from `listings`, 2% fee snapshot, `sellerId`/`storeId` on the order)
describes code that no longer exists on disk (only at git history) — this phase's real next step is
reconciling the two rather than resuming where the old code left off.

## PHASE 9 — Analytics + marketing

Not started.

## PHASE 10 — Admin

Not started (existing admin mock screens are marketplace-era, not this platform's admin panel).

## PHASE 11 — Internationalization

Not started. `platformServiceFeeRate` and `StoreModel.currencyCode` exist as seams; no multi-currency
conversion service yet.

## PHASE 12 — Security + production

Pulled forward and done this session (2026-09-11), because they're prerequisites for any later phase
touching real money or tenant data, not because PHASE 12 is next in sequence:

- Firestore rules: `users.role` self-escalation closed; `listings` ownership-checked; `orders` create
  locked to Cloud-Function-only.
- Secrets: `functions.config()` → `defineSecret`/`runWith({ secrets })` for CJ and IntaSend credentials
  (real values still need `firebase functions:secrets:set` before deploy — not set here).

Still open: Firebase custom claims (role still lives on a Firestore doc, just no longer
self-writable); rate limiting; Crashlytics/monitoring; backups; deployment runbooks; the emulator rule
suite for the two new rules above (add cases per `WORKLOG.md`'s verification section).

## Decisions still required

1. Payment custody model — platform collect-and-disburse vs. per-seller IntaSend accounts (see above).
2. Is CJ account ownership shared by Sellora or connected per seller?
3. Which payment provider has confirmed marketplace/split-payment capability, and its
   refund/settlement rules — gates resolving #1.
4. Are multi-store sellers required at launch?
5. Is `/s/:slug` accepted for MVP, with custom domains following later?

None of these block PHASE 1/2/8's completed slice above; they gate PHASE 3–7 and the rest of PHASE 8.
