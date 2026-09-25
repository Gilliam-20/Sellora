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
- The `listings` → `stores/{storeId}/products` write-path migration **landed 2026-09-18** (see
  WORKLOG.md) — `listProduct`/`updateListing`/`unlistProduct` and the `sellerListings`/
  `storefrontFeed`/`productDetail` reads all target the store-scoped subcollection now; flat
  `listings` is fully dead application code. The `orders` → `stores/{storeId}/orders` half of this
  is **still deferred** — that subcollection remains read-only and always empty until PHASE 8's
  order-creation Cloud Function is updated to write it.
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

2026-09-25: onboarding now opens with a store-setup step (name, category, country, currency, which
are new `StoreModel` fields). The shell's "you haven't created a store yet" branch routes there, and
that step creates the store if it's missing. Email-verification status and resend are shown during
setup.

Still open: a store switcher for multi-store sellers (today `resolveForSeller` just picks
`storesForSeller(sellerId).first`), gated on decision #4. Email verification is shown but not
required. No Google sign-in.

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
unit `Money` type, configurable pricing rules, import drafts.

**Done (2026-09-14, see `WORKLOG.md`):** the catalog-browsing plumbing is now reconciled with the
adopted backend — `ApiEndpoints`/`CjDropshippingService`/`FirebaseAdminRepository.syncCjCatalog`
call the real endpoint names (`searchProducts`/`getProductDetail`/`runCatalogSync`) with the real
query param names, unwrap the `{success, data, message}` envelope, and map the actual response field
names onto `ProductModel` (via new parsing helpers, not `ProductModel.fromMap`, which stays reserved
for the client's own persisted `listings` shape). The admin catalog-sync screen now triggers the real
server-side pipeline instead of a hand-rolled partial client-side sync into a dead `catalog` collection
(removed, along with its now-stale `firestore.rules` block).

**2026-09-25 correction:** the paragraph below (dated 2026-09-14) was stale — category browsing and
shipping-estimate UI shipped 2026-09-18/22 and this section was never updated to say so. Confirmed by
reading the code, not just commit messages: `SellerCatalogController.loadCategories()` →
`ProductRepository.categories()` → `CjDropshippingService.getCategories()` renders the catalog screen's
filter chip row; `ProductImportController._loadShippingEstimate()` and `CheckoutController`'s shipping
picker both call `CjDropshippingService.calculateFreight()`/`getShippingOptions()`. The CJ-catalog-to
per-seller-listing import mapping is also done — see the `product_import` screen described lower in this
section. What's still genuinely missing: a server endpoint for the *full* `marginPricingService.calculatePricing()`
formula (advertising/refund/VAT/fx-aware) — `ProductImportController.priceForMargin` does its own
simpler `landedCost * (1 + margin/100)` markup instead of calling that engine. Whether that's a real gap
or an intentional simplification is a product call, not a confirmed defect.

~~Still not started as app-facing work: any catalog browse/import screen actually using this plumbing;
`getCategories`/`calculateFreight` client methods (endpoints are correctly named in `ApiEndpoints` but
unconsumed — no category-browsing or shipping-estimate UI exists yet)~~ — see the 2026-09-25 correction
above. Real per-variant SKU/price/stock also still isn't representable client-side — `ProductVariant`
stays an attribute-picker (`{name, options}`) derived from the backend's richer per-SKU variant list,
not a purchasable-variant model; extending it is deferred until an import/variant-picker screen actually
needs it.

**Found 2026-09-14, `IntasendService` fixed the same day (see PHASE 8 below):** while reconciling
`ApiEndpoints`, `IntasendService`'s three order-checkout endpoint constants and
`FirebaseOrderRepository.placeOrder`'s request/response shape were confirmed to have the same class of
bug just fixed for catalog — both still targeted the old, deleted TypeScript backend's shapes. Digging
in turned up a deeper, genuine blocker rather than a same-day fix for both: `createOrder`'s real item
shape needs CJ's own `pid`/`vid` per line, and no `vid` (a purchasable per-SKU id) exists anywhere
client-side — `ProductVariant` is only `{name, options}` attribute strings. So `IntasendService` itself
was fixed (mechanical — see PHASE 8), but `FirebaseOrderRepository.placeOrder`/`CheckoutController`
were deliberately left broken: reconciling them for real needs a variant-id-carrying product model,
i.e. the import/variant-picker screen work directly above, not a client-side endpoint fix.

**Closed 2026-09-15 (model + wiring only, see WORKLOG.md):** `ProductVariant` now carries CJ's real
per-SKU `vid`/`sku`/`attributes`/price straight from `getProductDetail`'s variant list (previously
collapsed into an attribute-picker that discarded `vid` entirely). `ProductModel.toMap`/`fromMap` now
round-trip `variants`, so a real `vid` survives from CJ import through a seller's `listings` doc to
checkout. User explicitly scoped this to model + wiring — no seller variant-picker/import-detail screen
and no buyer variant-selector UI were built; a multi-variant product still imports and displays exactly
as before, just with real ids riding along underneath. See PHASE 8 below for how far this actually
unblocks checkout.

**Closed 2026-09-15, later same day (app-facing import screen, see WORKLOG.md):** the seller
variant-picker/import-detail screen named as missing above now exists —
`lib/modules/seller/product_import/`, pushed from the catalog list instead of the old flat-price bottom
sheet. Re-fetches the full CJ detail (search results carry no description/variants), shows a real image
gallery, a variant chip picker priced against that SKU's own CJ cost, and a smart-pricing card (quick
margin presets + an editable price field with a live profit/margin readout) feeding `listProduct`'s new
`isListed` flag for save-as-draft vs. publish. Still no buyer-facing variant selector (buyer product
detail still auto-picks `variants.first`) and still no category browsing or shipping-cost estimate UI —
`getCategories`/`calculateFreight` remain unconsumed `ApiEndpoints`, unchanged from 2026-09-14. Also
fixed in passing: `MyListingsController`/`SellerDashboardController` only loaded their data once in
`onInit()` and never refreshed on tab-switch (`SellerShellView` keeps every tab alive in one
`IndexedStack`) — a seller importing a product wouldn't see it in My listings or the dashboard's
listing count without leaving and re-entering the seller shell. Fixed by having the import screen call
`.load()` on both after a successful write.

## PHASE 5 — Seller product management

Store-scoped products/variants/inventory/collections/SEO, server-authorized write paths, paginated
query contracts, responsive list/table/grid states, bulk operations.

**Done (2026-09-18, see WORKLOG.md):** the write-path migration this phase was blocked behind —
`ProductModel` gained `storeId`; `listProduct`/`updateListing`/`unlistProduct` now write
`stores/{storeId}/products` instead of flat `listings`; `sellerListings`/`storefrontFeed`/
`productDetail` moved to a `products` collection-group query so they don't silently break once
`useMockData` flips off. `My Listings`/`Product Import`/dashboard call sites updated accordingly.
Deliberately scoped to just the write path, per user decision — everything else below is still not
started.

**Done (2026-09-18, see WORKLOG.md):** variants management UI — `ProductVariant` gained `enabled`
(seller-controlled visibility switch) and stayed editable for its own `sku`; a new
`lib/modules/seller/manage_variants/` screen, reachable by tapping a listing in My Listings, lets a
seller toggle which imported SKUs a buyer can pick and rename their own SKU reference.
`ProductModel.visibleVariants` filters the buyer-facing picker in `product_details_view.dart`
accordingly (`_BuyerVariantPicker` — a real picker, not an auto-pick-first; only the price stays fixed
per listing regardless of variant, by design, per `ProductVariant`'s own doc comment). Deliberately left
CJ's own attributes/price/costPrice/image read-only, and deliberately did not add per-variant pricing (touches checkout's `CartItemModel.lineTotal` and the server-side
`createOrder` re-pricing — its own scoped pass) or per-variant stock (that's this phase's own "real
inventory tracking" item, not to be half-done here).

Not started: collections, real inventory tracking beyond the flat `stock` int, SEO fields (meta
title/description/slug), bulk select/edit/delete, pagination on any of the list reads above (all
still unbounded `.get()` calls), and server-authorized writes (today's write path is still a direct
client Firestore write gated only by security rules, not a Cloud Function re-validating plan
limits/ownership the way `createOrder` does for orders).

## PHASE 6 — Store builder

Theme/section/block/setting models, renderer/preview/publish flow. Mostly not started.

**2026-09-19 update:** a first, narrow slice shipped — a seller-facing "Customize store" screen
(`lib/modules/seller/store_customize/`) editing the branding fields `StoreModel` already had (name,
tagline, logo URL, banner URL, accent color hex), reachable from the seller profile screen. The
storefront (`StorefrontView`) now renders the logo/banner and uses the accent color for the selected
category chip. See `WORKLOG.md`'s 2026-09-19 entry. Still not started: theme/section/block/setting
models, a renderer, a preview flow, a publish flow, and threading `primaryColorHex` anywhere beyond
that one storefront chip row.

**2026-09-20 update:** logo/banner fields were URL-paste-only, which isn't something a real seller
can use. `StoreCustomizeController` can now pick a photo from the device (`image_picker`) and inline
it as a `data:` URI into the same `logoUrl`/`bannerUrl` string fields — no `firebase_storage` upload
step exists yet, so this is what makes it actually usable today, in both mock and Firestore-backed
modes. See `WORKLOG.md`'s 2026-09-20 entry for the size-limit and rendering details.

## PHASE 7 — Customer storefront

Replace the shared buyer feed with `/s/:slug` storefront pages, store-bound carts, customer profiles
beneath that store.

**2026-09-20 update:** core shopping flow done — see `WORKLOG.md`'s 2026-09-20 entry for the full
change list. `Routes.storefront` (`/s/:slug`) is now the buyer shell itself (shop/cart/orders/alerts/
profile tabs), reachable by guests and signed-in buyers at the same URL; the old flat `/buyer` shell
and its duplicate feed (`BuyerHomeController`/`BuyerHomeView`, which read `sellerListings()` separately
from `StorefrontController`'s `storeProducts()`) are deleted. Product details and checkout are now
`/s/:slug/product` and `/s/:slug/checkout` — guest-reachable for browsing/cart, with checkout gating
its own submit step behind sign-in rather than route middleware. `BuyerShellController` resolves
`StoreScope` from the route the same way `SellerShellController` does for the seller side.

Still not started: collections (needs PHASE 5's model first — no collection concept exists yet), a
dedicated `Customer` model or any reads of `stores/{storeId}/customers` (still just a write-once mirror
of the `users/{uid}` doc, per the 2026-09-08 decision log), an order-detail/tracking screen (order
*history* exists, a single order's fulfillment detail doesn't), a multi-store switcher, and any
search/SEO work beyond the existing keyword/category filter. Order writes still land in the flat
`orders` collection — `stores/{storeId}/orders` is read-ready but nothing writes there, since the
adopted Cloud Functions backend has no store concept server-side at all (PHASE 8's problem, not
touched here).

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

**2026-09-14 update:** `IntasendService` (order-checkout payment) reconciled with the adopted backend —
`payOrderMpesa`/`payOrderCard`/`confirmOrderPayment` now call the real endpoints with the real
`{orderId, ...}` request shape and unwrap the real `{success, data}` response, replacing the old
client-computed-amount `collectMpesa`/`createCheckout`/`checkStatus` (dead code beyond one call site,
same pattern as `CjDropshippingService`'s earlier dead-code removal). `CheckoutController`'s one call
site was updated to compile against the new signature. Confirmed, not fixed: `createOrder`'s side of
the flow (`FirebaseOrderRepository.placeOrder`) is genuinely blocked, not just unstarted — see the PHASE
4 note above. So `IntasendService` is now correct in isolation, but nothing in the app can reach it with
a valid order id yet.

**2026-09-15 update:** the per-SKU variant-id blocker named above is closed at the model layer (see
PHASE 4's 2026-09-15 note) and threaded all the way through: `CartItemModel.selectedVariant` is now a
real `ProductVariant`, `OrderItem` carries `cjProductId`/`variantId`, and
`FirebaseOrderRepository.placeOrder` sends `createOrder` the correct `{pid, vid, quantity}` per item.
This closes exactly one of the two things blocking real checkout, confirmed by reading
`functions/lib/orders.js` directly: `createOrder` also requires `shippingAddress.countryCode` (a
structured object) where `CheckoutController` only ever collects a free-text address string, and its
response (`{id, totalAmount, currency, items, ...}`) has no `orderId`/`code`/`serviceFeeAmount` for
`placeOrder`'s return mapping to read — both deliberately left alone this pass (user scoped it to
variant-id wiring only), and both are the same class of "reconcile two different checkout models"
problem flagged since 2026-09-12, not new discoveries. Checkout end-to-end is still blocked, just on a
smaller, more precisely-named remainder than before.

**2026-09-15 update (later same day):** both remaining items above are closed, client-side only (user's
explicit scope choice — see `WORKLOG.md`). `OrderModel.shippingAddress` is now a `ShippingAddress`
(`{countryCode, line}`); `CheckoutView` collects a country; `FirebaseOrderRepository.placeOrder` sends
that shape and reads the real `{id, totalAmount, currency, items, ...}` response instead of the
nonexistent `orderId`/`code`/`serviceFeeAmount`. Checkout is no longer blocked on a named mechanical gap.
What's left is the real fork flagged in the 2026-09-12 update above, now sharper: `OrderModel`'s
`sellerId`/`storeId`/`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue`/`paymentFee` are client-side
bookkeeping only — the adopted backend computes and stores none of them, so the 2% platform fee this
whole product is named after isn't actually collected by any order today. Closing that for real means
either adding seller/store/fee support to `functions/lib/orders.js`, or making a deliberate call that
single-vendor is fine for now and those fields should shrink/go away. Separately, `shippingAddress.line`
is still one free-text field, not the `{fullName, phone, email, line1, line2, city, province, zip}` shape
`functions/lib/cjApi.js` needs to actually push a fulfillment to CJ later.

**2026-09-25 update — seller/store attribution + fee split scaffolded (see WORKLOG.md):** closes the
fork above by adding seller/store support rather than dropping the fields. `createOrder` now requires
`storeId`, prices every line at the seller's own `stores/{storeId}/products/{pid}.sellPrice` (previously
it silently re-derived its own price from CJ's cost via a single global margin, ignoring the seller's
price entirely — a deeper gap than "missing fields," found while doing this pass), and snapshots
`buyerId`/`sellerId`/`storeId`/`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue` (2% of product
subtotal only, via a new pure, unit-tested `splitServiceFee`). `buyerId` being unset was also the exact
gap flagged in today's earlier PHASE 12 WORKLOG entry's "Still open" list (`FirebaseOrderRepository.buyerOrders`
queries a field no order carried) — closed as a side effect. `stores/{storeId}/orders` is now written
(previously always empty) but only at creation — nothing later (`attachPaymentAttempt`, the payment
webhooks, `refundOrder`, `retryFailedFulfillments`, `refreshOrderTracking`) mirrors its updates there
yet, flagged inline in `orders.js`; harmless today since no screen reads that path (`sellerOrders`, the
one the seller order queue/dashboard call, already works off the flat `orders` collection and is
unaffected). `functions/test/orders.test.js` gained 4 cases; `functions` suite and the `firestore-tests`
emulator rules suite (unchanged, no rules edits needed) both pass in full.

**Deliberately not done this pass (user's explicit "scaffold, not full implementation" choice):** no
real IntaSend Split Payments sub-account wiring — money still moves exactly as before, one charge, no
split, no payout. The five API specifics from the 2026-09-09 design entry (split precision, sub-account
KYC turnaround, Payouts API minimums/fees, settlement schedule, refund-on-split behavior) are still
unconfirmed against a real IntaSend account and are what actually blocks turning this snapshot into a
real payout. Also not attempted: driving `createOrder` itself through the Firestore/functions emulator
— no mocked-CJ-API test harness exists for this file's async paths (same as before this pass; only its
pure helpers are unit-tested, consistent with how the rest of this file is already tested).

## PHASE 9 — Analytics + marketing

Dashboard-analytics slice shipped 2026-09-21 (see WORKLOG.md) — the seller Home screen now has
real date-range-filtered metrics, a sales chart, order-status breakdown, top products, a
store-health/subscription-usage card, and a guided setup checklist. Not started: discount codes,
a `CustomerModel` and customer analytics, and marketing campaigns/tools (deferred — see WORKLOG.md
for why).

## PHASE 10 — Admin

First slice shipped 2026-09-22 (see WORKLOG.md). Correction to this doc's own earlier framing: the
existing admin shell (Overview/Sellers/Sync/Orders/Plans) was never marketplace-era mock UI — every
tab already read `AdminRepository`/`OrderRepository`/`SubscriptionRepository` against whichever
backend is active (real or mock), same as the rest of the app. What Overview was actually missing was
TODO.md §35's platform financial model (seller GMV kept separate from Sellora's own service-fee and
subscription revenue) — it only had a single undifferentiated "Total GMV" tile. That's fixed now, plus
a new Stores tab surfacing `StoreRepository.allStores()` (already implemented, never wired to any
screen). Not started: store suspension (no status field exists on `StoreModel` yet — piggybacking on
the owning seller's `SellerStatus` was a deliberate call this session, not an oversight), refunds UI,
coupons, categories, themes, feature flags, platform settings, reports/support, and churn (no
historical snapshot to compute it from yet).

## PHASE 11 — Internationalization

First slice shipped 2026-09-25 (see WORKLOG.md). Done: currency registry (KES/USD/GBP/EUR) and a
`Money` minor-unit type in `lib/core/i18n/`; `CurrencyService` converting all four from the server's
`config/fx` rate cache (`FxRateRepository`, Firebase + mock); a country/shipping-zone/payment-method
registry mirroring `functions/lib/regions.js`, with a test that fails on drift; per-store
`shippingZones` editable in Customize store and applied to checkout's country list; card payment via
IntaSend's hosted page for non-Kenyan buyers; `flutter_localizations` wired (English only). Still open:
server-side zone enforcement (blocked on the same store-less `createOrder` as PHASE 8), non-KES
settlement, a real `PaymentProvider` interface, minor-unit persisted amounts, ARB string extraction.

## PHASE 12 — Security + production

Pulled forward and done this session (2026-09-11), because they're prerequisites for any later phase
touching real money or tenant data, not because PHASE 12 is next in sequence:

- Firestore rules: `users.role` self-escalation closed; `listings` ownership-checked; `orders` create
  locked to Cloud-Function-only.
- Secrets: `functions.config()` → `defineSecret`/`runWith({ secrets })` for CJ and IntaSend credentials
  (real values still need `firebase functions:secrets:set` before deploy — not set here).

2026-09-25 audit pass (see `WORKLOG.md`'s PHASE 12 entry for the full findings table): closed admin
self-escalation via user-doc *create*, client-creatable store orders, seller/admin writes to order
payment fields, store-slug hijacking (`store_slugs` reservations), missing per-user rate limits,
upstream error messages leaking to clients, unvalidated freight/phone/redirect inputs, and revoked
tokens being accepted. Rules now honour the `admin` custom claim. Emulator suite: 33 cases.

Still open: drop the `role() == 'admin'` fallback once admins carry the claim; App Check enforcement
(client doesn't send tokens yet); Crashlytics/monitoring; Firestore backups + a TTL policy on
`rate_limits.expireAt`; deployment runbooks; untrack `functions/node_modules`.

## Decisions still required

1. Payment custody model — platform collect-and-disburse vs. per-seller IntaSend accounts (see above).
2. Is CJ account ownership shared by Sellora or connected per seller?
3. Which payment provider has confirmed marketplace/split-payment capability, and its
   refund/settlement rules — gates resolving #1.
4. Are multi-store sellers required at launch?
5. Is `/s/:slug` accepted for MVP, with custom domains following later?

None of these block PHASE 1/2/8's completed slice above; they gate PHASE 3–7 and the rest of PHASE 8.
