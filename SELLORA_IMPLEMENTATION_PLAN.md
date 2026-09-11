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
all after signing up).

Still open: route middleware/guard for seller-admin routes (nothing blocks navigation while the store
is resolving or missing); a store switcher for multi-store sellers (today `resolveForSeller` just picks
`storesForSeller(sellerId).first`); onboarding completion state and plan selection (folds into
PHASE 3).

## PHASE 3 — Billing

Plan schema (Starter/Growth/Pro per TODOD §16, configurable rather than hard-coded), immutable
subscription/billing records, usage tracking, provider-neutral subscription payments. Not started.
Note: `FirebaseSubscriptionRepository.subscribeSeller` currently writes `billing_history` directly from
the client, which `firestore.rules`' `allow write: if false` on that collection already silently
blocks against real Firestore — this phase needs to move that write server-side, the same way PHASE 8
just did for orders.

## PHASE 4 — Catalog, pricing, and CJ import

Confirm the CJ account/API contract, add a supplier adapter, shipping quote contract, integer-minor-
unit `Money` type, configurable pricing rules, import drafts. Not started.

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
