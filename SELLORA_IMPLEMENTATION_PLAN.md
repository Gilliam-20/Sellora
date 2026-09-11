# Sellora Implementation Plan

## Guardrails

Preserve the current GetX/repository split, mock mode, and working portals while a replacement is built. Each repository contract change includes mock and Firebase implementations. No payment, fulfillment, fee, or Firestore-rule migration ships without tests and Firebase Emulator verification.

## Phase 1 — Foundation (started)

Deliverables: the #FFC107 / #303F9F Sellora theme pair, system dark mode, shared page/header/search/loading/error primitives, unified breakpoints, and a documented route/component convention. The current responsive shell and Meridian signature card are retained. The seller dashboard now uses the shared page-header primitive.

Exit criteria: `flutter analyze`, widget tests for new primitives, and web build pass. This phase intentionally does not alter business data, payments, CJ calls, or security rules.

## Phase 2 — Tenant core (started)

Add a `StoreScope` that resolves `/s/:slug`, a public-store lookup cache, and store-scoped route middleware. Add repository methods keyed by `storeId`; migrate mocks first, then Firestore paths. Define the collection indexes and write emulator tests proving one seller cannot query another seller's products, orders, customers, settings, or payments.

Done so far: `StoreScope` + `/s/:slug` + `StorefrontView`; `storeProducts()`/`storeOrders()` read methods (mock + Firebase) with matching Firestore rules; `firestore-tests/` emulator suite proving tenant isolation on products/orders/customers. Still open: store-scoped route middleware for seller-admin routes, the `placeOrder`/product-create write-path migration onto the new subcollections, and store-scoped `settings`/`collections`. See `WORKLOG.md` (2026-09-11) for the full detail.

## Phase 3 — Seller onboarding and entitlements

Normalize seller/store creation, country/currency, onboarding completion, active store selection, plan definitions, and feature flags. Model limits as plan data, never UI constants.

## Phase 4 — Catalog, pricing, and import

Confirm the CJ account/API contract. Add a supplier adapter, shipping quote contract, `Money` minor-unit type, configurable pricing rules, and import drafts. Compute recommendations server-side or in a deterministic shared domain service; sellers may override only their selling price.

## Phase 5 — Seller product management

Build store-scoped products/variants/inventory/collections/SEO, with server-authorized write paths and paginated query contracts. Add responsive list/table/grid states and bulk operation confirmation flows.

## Phase 6 — Store builder and storefront

Create theme, section, block, and setting models plus renderer/preview/publish flows. Replace the shared buyer feed with `/s/:slug` storefront pages, store-bound carts, and customer profiles beneath that store.

## Phase 7 — Billing, payments, and orders

Choose and verify the marketplace payment operating model before implementation. Build a provider interface, signed webhooks, idempotent order creation, server repricing, fulfillment state machine, refunds, and payment ledger. Snapshot `serviceFeeRate = 0.02`, `serviceFeeAmount`, `paymentFee`, `sellerRevenue`, and currency on each successful order; do not charge service fee on shipping/tax unless configured.

## Phase 8 — Operations and launch hardening

Add analytics, discounts, customer tools, notifications, platform admin reporting, custom-claim administration, Secret Manager migration, monitoring/Crashlytics, rate limits, backups, full test coverage, and deployment runbooks.

## Decisions required before data/payment migration

1. Is there any production Firebase data to migrate?
2. Is CJ account ownership shared by Sellora or connected per seller?
3. Which payment provider has confirmed marketplace/split-payment capability and its refund/settlement rules?
4. Are multi-store sellers required at launch?
5. Is `/s/:slug` accepted for MVP, with custom domains following later?
