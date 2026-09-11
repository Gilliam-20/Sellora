# Sellora Architecture Audit

Audit date: 11 September 2026. This document records the repository as found. It does not represent a claim that the Firebase or payment path is production-ready.

## A. Existing architecture

The Flutter app uses a feature-oriented presentation layer under `lib/modules`, GetX for routing, dependency injection, and observable view state, and a `View → Controller → Repository → Service` layering. `InitialBinding` installs durable services and repository implementations once; route bindings lazily create controllers. Domain models are plain Dart objects in `lib/data/models`.

`AppConstants.useMockData` is currently `true`; mock repositories therefore power every runtime path. Real repositories are present but unexercised scaffolding. Cloud Functions proxy CJ Dropshipping and IntaSend so provider secrets are not embedded in the client.

## B. Existing features

Implemented and demoable in mock mode: role-based sign-in and registration, seller onboarding and subscription selection, seller catalog browsing/listing/order queue/profile, a shared buyer catalog/cart/checkout/order history, and admin seller/catalog/order/plan views. Store records and a store-picker/customer profile concept already exist.

## C. Existing screens

- Auth: splash, role choice, sign-in, buyer and seller registration, store selection.
- Seller: dashboard, CJ catalog, listings, orders, profile, subscription, onboarding.
- Buyer: home/feed, product detail, cart, checkout, orders, profile.
- Admin: overview, sellers, catalog sync, orders, plans.

These are portal tabs, not the Shopify-class route tree requested for the seller admin or a standalone storefront renderer.

## D. Existing Firebase structure

Current service paths are `users`, `catalog`, `listings`, `orders`, `subscription_plans`, `billing_history`, `stores`, and `stores/{storeId}/customers`. The existing flat `listings` and `orders` collections retain marketplace-era data ownership. `StoreModel` already has an id, slug, seller id, identity/branding fields, and currency code, which is a useful starting point for migration.

## E. Existing Firestore rules

Rules expose public stores/listings and allow signed-in users to read all `users` documents. Seller listing writes are role-gated but are not checked against the listing's owner/store. Orders are flat and client-created, and the user role is read from a client-writable Firestore document. These rules must be replaced before real data or money is handled. The existing `stores/{storeId}/customers` rule is the only tenant-scoped resource today.

## F. Existing CJ integration

`CjDropshippingService` calls authenticated HTTPS functions. `functions/src/cj.ts` gets a platform-level CJ token and proxies product search/detail, fulfillment, and tracking. Its endpoints and field mapping are explicitly provisional and require validation against a real CJ account. A shared CJ credential is incompatible with per-seller cost ownership until a commercial/settlement decision is made.

## G. Existing payment integration

`IntasendService` supports M-Pesa STK initiation, hosted checkout creation, and status polling via Cloud Functions. The webhook only logs payloads; it does not verify signatures or mutate subscription/order state. Checkout writes client-calculated totals/payment references, and the order trigger does not independently confirm payment before fulfillment. No provider abstraction, immutable payment ledger, refund flow, or 2% historical platform-fee snapshot exists.

## H. Existing GetX architecture

The lifetime split is sound: `InitialBinding` holds permanent infrastructure, while feature bindings lazily create controllers. Controllers generally delegate to repositories. The main architectural conflict is semantic rather than GetX-specific: buyer/storefront controllers and flat repositories still model a shared marketplace. All repository interface changes must retain both mock and Firebase implementations.

## I. Existing navigation

Routes are centralized in `app/routes`; `RoleMiddleware` protects buyer, seller, and admin shells and redirects unsubscribed sellers to onboarding. The portals use a responsive tab shell: bottom navigation on smaller viewports and a navigation rail on desktop. There are no canonical seller CRUD/detail routes, no `/s/:slug/...` public storefront route tree, and no store-scope middleware.

## J. Existing reusable widgets

The Meridian system provides colors, typography, metrics, `ManifestStub`/`ManifestStatCard`, product cards, `EmptyState`, loader, section header, bottom action bar, responsive sizing/centering/grid helpers, and the adaptive portal shell. Phase 1 adds a system-aware dark theme and shared page/header/search/loading/error primitives in `core/widgets/app_page.dart`.

## K. Technical debt and risks

- The app is mock-first; Firebase initialization is disabled in the active configuration.
- Financial values use `double`; money must migrate to integer minor units before payment/order work.
- Role authorization relies on Firestore data writable by the user; use Firebase custom claims plus server-side validation.
- Public/flat listing and order paths can leak tenants when a query constraint is missed.
- There is no automated Firestore emulator rule suite (Dart unit tests exist under `test/`).
- The original buyer marketplace remains alongside the planned store-scoped model; it must be retired only through a measured migration.

**Findings from the 2026-09-11 follow-up audit (fixed same session — see `WORKLOG.md`):**

- `firestore.rules` let any signed-in user set their own `users/{uid}.role` field to `'admin'` on
  update, self-escalating past every `role() == 'admin'` check in the ruleset. Fixed: `role` can now
  only change via an existing admin.
- `listings/{listingId}` write rule checked only `role() == 'seller'`, not ownership — any seller
  could edit or "steal" any other seller's listing. Fixed: create/update now require
  `sellerId == request.auth.uid` and forbid reassigning `sellerId`.
- `functions/src/orders.ts`'s `onOrderCreated` trigger POSTed to the authenticated `cjCreateOrder`
  HTTPS function with no `Authorization` header — it would 401 on every real order. Fixed by removing
  the HTTP self-call: `cj.ts` now exports a plain `placeCjOrder()` function called in-process, and only
  from the IntaSend webhook once payment is actually confirmed (previously fulfillment could start
  before payment was verified at all — the trigger's own comment already flagged this).
- `functions/src/intasend.ts`'s `intasendWebhook` was a stub — logged the payload, verified nothing,
  never touched Firestore, so no payment was ever confirmed anywhere. Fixed: verifies a shared
  "challenge" value (needs reconfirming against IntaSend's current docs before go-live) and updates
  the matching order's `paymentStatus`/triggers fulfillment.
- Checkout was fully client-trusted — `CheckoutController` computed `total` and wrote
  `paymentReference` itself; `FirebaseOrderRepository.placeOrder` just `.set()` the client's doc
  verbatim. Fixed: a new `createOrder` Cloud Function re-prices every item from its `listings` doc
  server-side; `orders/{orderId}` create is now `allow create: if false` in rules, so no client path
  can write an order doc directly anymore.
- `functions.config()` (used for CJ/IntaSend credentials) is deprecated in the installed
  `firebase-functions` version, and no `.env`/`.runtimeconfig.json` existed — a fresh deploy would call
  CJ/IntaSend with `undefined` credentials. Migrated to `defineSecret`/`runWith({ secrets: [...] })`;
  real values still need to be set with `firebase functions:secrets:set` before any real deploy.
- `AuthRepository.signUpSeller` (mock and Firebase) never created a `StoreModel` — a freshly-registered
  seller had no store at all. Fixed in both implementations.

## L. Missing features

The requested seller navigation, store-scoped catalog/products/orders/customers, product import editor, pricing engine, configurable plan limits, billing ledger, storefront section/theme renderer, customer storefront, payment provider abstraction, shipping/tax/discount/SEO/domain systems, analytics, notifications, admin financial controls, observability, and production security are not implemented. UI-only mock flows must not be presented as backend-complete features.

## M. Recommended target architecture

Keep GetX, Dio, Firebase, and the mock/real repository seam. Migrate every merchant-owned aggregate beneath `stores/{storeId}`: products, orders, customers, collections, discounts, settings, domains, analytics, and private payment data. Keep only platform-wide identities, plans, supplier catalog, platform orders, and notifications top-level. Introduce `StoreScope` resolved from `/s/:slug` and a repository API that always accepts a `storeId`; use collection-group queries only for authorized admin reporting.

Represent currency as `{minorUnits, currency}` and snapshot all applicable price/cost/fee rates on a confirmed order. Place order creation, repricing, payment verification, fee calculation, and fulfillment orchestration in idempotent Cloud Functions. Authorize users with custom claims and validate ownership on every server/database boundary.

## N. Exact implementation phases

1. Foundation: design tokens/themes, responsive admin shell, shared page states, route conventions, error boundaries, test harness.
2. Tenant core: `StoreScope`, `/s/:slug` resolution, store-owned repository paths, dual mock/Firebase migration, rules and emulator tests.
3. Seller identity/onboarding: seller profile, store creation, currency/country, configurable plan selection and entitlement checks.
4. Billing: plan schema, immutable subscription/billing records, usage tracking, provider-neutral subscription payments.
5. Catalog/import: verified CJ adapter, catalog search/detail, shipping quote, integer-money pricing engine, import draft workflow.
6. Seller commerce: store-scoped products, variants, inventory, collections, search/filter/bulk operations, SEO.
7. Store builder/storefront: theme sections, preview/publish, public `/s/:slug` routes, customer accounts/cart.
8. Orders/payments: provider abstraction, server order state machine, confirmed payment/webhooks, 2% immutable fee records, fulfillment/refunds.
9. Growth: customers, analytics, discounts, marketing, notifications.
10. Admin/production: controls, reports, claims/rules/secrets/rate limits, Crashlytics, performance, release validation.

## O. Files to modify first

`lib/main.dart`, `lib/app/theme/*`, `lib/app/routes/*`, `lib/app/bindings/initial_binding.dart`, `lib/core/widgets/*`, `lib/core/utils/responsive.dart`, `lib/data/services/firestore_service.dart`, all affected repository interfaces plus both implementations, `firestore.rules`, `firestore.indexes.json`, and `functions/src/*`. Existing buyer modules must not be deleted until the store-scoped storefront replaces them.

## P. Files/directories to create

- `SELLORA_IMPLEMENTATION_PLAN.md` and this audit.
- `lib/core/money/money.dart`, `lib/core/money/currency_service.dart`, and tests.
- `lib/app/middleware/store_scope_middleware.dart`, `lib/features/storefront/store_scope.dart`.
- Store-scoped product/order/customer repository/service/model files as each phase is reached.
- `functions/src/orders/create_order.ts`, `functions/src/payments/*`, and verified webhook handlers.
- `test/` unit/widget tests and `functions/test/` integration tests; Firestore emulator rules tests.

No schema or security migration is applied in Phase 1: production data status and the documented payment/CJ operating-model decisions must be confirmed before that destructive boundary is crossed.
