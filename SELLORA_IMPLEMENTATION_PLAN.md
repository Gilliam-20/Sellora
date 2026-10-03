# Sellora Implementation Plan

Current state per phase, on the Supabase backend. Dated history (the Firebase-era steps, the
backend swaps, why each call was made) lives in `WORKLOG.md`; the security posture is in
`SELLORA_SECURITY_AUDIT.md`.

## Guardrails

Keep the GetX View → Controller → Repository split. Every repository contract change updates its
`Supabase*` implementation and the matching fake in `test/fakes/`. Any schema or policy change is a
new migration in `supabase/migrations/` with a check in `supabase/tests/rls.test.mjs`. No payment,
fulfillment or fee change ships without tests (`flutter test`, `cd supabase && npm test`).

## Phase framework

Phases follow `TODO.md`'s `PHASE 0`–`PHASE 12` numbering (its "master build prompt"). `TODO.md` is an
aspirational reference, not a spec to execute section by section.

## Decisions on record

- Platform service fee: **7%** of the order's product subtotal (raised from 2% on 2026-09-26),
  computed server-side by `splitServiceFee` in `supabase/functions/_shared/orders.js` and snapshotted
  on the order (`service_fee_amount`, `seller_revenue`). Never on shipping/tax, never rewritten on
  historical orders.
- Store-scoped data: `products` is keyed `(store_id, id)` and every order carries `store_id` and
  `seller_id`. Buyers read `storefront_products`; sellers read their orders through `seller_orders`.
- Payment custody (platform collect-and-disburse vs. per-seller IntaSend accounts) is still **open**.
  Order creation and webhook confirmation work under either model.
- CJ account model is still **open**: one platform credential (`CJ_API_KEY`).

## PHASE 0 — Audit: done

The original Firebase-era audit is superseded by `SELLORA_SECURITY_AUDIT.md` (2026-09-26).

## PHASE 1 — Foundation: done

Sellora theme pair (#FFC107 / #303F9F) on the Meridian system, system dark mode, shared
page/header/search/loading/error primitives, unified breakpoints, responsive shell.

## PHASE 2 — Auth + seller onboarding: in progress

Done: the `handle_new_user` trigger creates the profile and a seller's store at sign-up; `StoreScope`
resolves `/s/:slug` and a signed-in seller's own store; the marketing page is the signed-out entry
point; the seller shell guards on store resolution; onboarding opens with a store-setup step (name,
category, country, currency) and shows email-verification status with resend; password reset, the
Android `sellora://auth-callback` deep link and an expired-link screen.

Still open: a store switcher for multi-store sellers (`resolveForSeller` picks the first store; gated
on decision #4), required email verification, Google sign-in.

## PHASE 3 — Billing: done except cancel/resume

`subscribeSeller` and the `payBilling*`/`confirmBillingPayment` routes are server-side; only a
confirmed payment activates a plan (`activate_subscription`). `billing_history`/`subscriptions` have
no client write policy. Plans carry configurable listing/order/store limits; the server enforces all
three (audit §6, H6), and the app reads usage from `my_plan_usage()`. The subscription screen has
Renew, billing history and a plan comparison. A downgrade below the seller's listed count is refused,
with a trigger backstop. Plans are admin configuration (TODO.md §16, 2026-10-03): seeded launch plans,
a full editor with create/retire, database bounds on every field, and plan cards built from the
configured limits and features.

Not built: cancel/resume (there's no auto-renewal; an unpaid plan lapses). Proration on a mid-period
upgrade is an owner decision.

## PHASE 4 — Catalog, pricing, CJ import: done in code

Catalog search/detail/categories/freight go through the `api` function (seller/admin only). The seller
import screen (`lib/modules/seller/product_import/`) has a variant picker, a shipping estimate, and a
pricing card whose earnings readout matches the real split (price − 7% fee − CJ cost; the buyer pays
shipping). `ProductVariant` carries CJ's per-SKU `vid`/`sku`/price. Admin catalog sync runs the
server pipeline into `catalog_products`/`catalog_categories`. The hourly `syncListings` job
(`_shared/listingSync.js`) refreshes CJ cost for listed products and flags (`products.supplier_alert`)
and notifies on a listing checkout would refuse; it never unlists.

Still open: CJ's auth handshake and response shapes are unconfirmed against a real account; whether a
server-side full `marginPricingService` quote is wanted is a product call.

## PHASE 5 — Seller product management: partial

Done: listing/draft/unlist writes to `products`, gated by RLS and the publishing/plan-limit triggers;
variants management (`lib/modules/seller/manage_variants/`) to enable/disable SKUs and set the seller's
own SKU reference; paged reads for listings and the storefront.

Not started: collections, inventory beyond the flat `stock` int, SEO fields, bulk operations,
per-variant pricing.

## PHASE 6 — Store builder: first slice

"Customize store" (`lib/modules/seller/store_customize/`) edits name, tagline, logo, banner and accent
color. Logo/banner upload to the `store-media` Storage bucket (stores branded before 2026-09-27 keep
their inline `data:` images until re-uploaded). The storefront renders them.

2026-10-03 (TODO §18): the store builder. `StoreDesign` (`lib/data/models/store_design.dart`) is the
Store → Theme → Sections → Blocks → Settings model, with each section type's settings described by a
schema that drives both the builder's generic editor and validation. `StorefrontRenderer`
(`lib/modules/storefront/design/`) renders it for buyers and for the builder's preview. Seller →
Store design (`lib/modules/seller/store_builder/`) edits a draft and publishes it (`store_designs`,
`publish_store_design()`, `storefront_designs`). A store that never published shows
`StoreDesign.starter`: its banner as a hero, then the catalog.

2026-10-04 (TODO §19): themes. `StoreTheme` (`lib/data/models/store_theme.dart`) defines General
Store, Minimal, Modern, Fashion and Electronics in code: version, drawn thumbnail (`ThemeThumbnail`),
settings including the new layout style (`StoreStyle` in the renderer) and a starter homepage. The
builder's Theme panel applies one, with or without its homepage. No database change.

Still open: real collections (the collections section opens a category), admin-managed themes and a
per-store theme library,
theming the product/cart/checkout pages, design history beyond draft/live.

## PHASE 7 — Customer storefront: core flow done

`/s/:slug` is the buyer shell (shop/cart/orders/alerts/profile), guest-reachable for browsing and
cart; product detail and checkout live at `/s/:slug/product` and `/s/:slug/checkout`, with checkout
requiring sign-in at submit. The old flat `/buyer` shell is gone.

2026-10-04 (TODO §20): the storefront as its own site. One route per page under `/s/:slug` (see
`Routes.storefront*` and `StorefrontPaths`); `StorefrontSession` loads the store, published design,
pages and categories once for whichever page is opened first; `StorefrontFrame`/`StorefrontPage`
(`lib/modules/storefront/shell/`) give every page the store's theme, header, drawer and footer. New
pages: shop, search, collections (categories) and one collection, a deep-linkable product page, the
cart, the order confirmation/detail page, account and order history, and the seller-written About,
Contact and policy pages (`store_pages`, `storefront_pages`, Seller → Store pages). The tabbed buyer
shell is deleted.

Not started: a real collection model, a `CustomerModel` reading `store_customers`, a multi-store
switcher, SEO (needs server-rendered meta tags), sign-in/register in the store's theme.

## PHASE 8 — Payments + orders: done in code, never run live

Done: `createOrder` prices every line from the seller's own `products.sell_price` (never a client
total), requires one store per cart, snapshots buyer/seller/store and the fee split, and writes the
order with its server-only columns. Checkout offers M-Pesa (Kenya) and card via IntaSend's hosted
page. `intasendWebhook` verifies the optional `INTASEND_WEBHOOK_CHALLENGE`, confirms payment
(`webhook_events` dedupes), and pushes fulfillment to CJ with a compare-and-set claim; a cron job
retries failed pushes and another refreshes tracking. `OrderPaymentStatus` includes
`partiallyRefunded`/`refunded`. Refunds exist server-side (`_shared/refunds.js`, admin-only
`/refundOrder`).

2026-10-03: Admin → Orders opens a refund sheet per order (charged amount in KES, refunded so far,
history, last failure, full or partial refund with an IntaSend reason). It reads the admin-only
`admin_order_refunds` view and posts `ApiEndpoints.refundOrder`. `ShippingAddress` is now
`{fullName, phone, email, line1, line2, city, province, zip, countryCode}`; `createOrder` normalizes it
and refuses one missing name/phone/street/city (`normalizeShippingAddress`), and `fulfillOrder`
re-checks it before pushing to CJ. Checkout pays through `OrderPaymentProvider`
(`lib/data/services/order_payment_provider.dart`), which `IntasendService` implements.

Still open: mixed-seller carts are rejected, not split (needs a decision: one payment across several
orders, or one checkout per store); no real split payout (money moves as one charge); the server's
payment routes (`payOrderMpesa`/`payOrderCard`/webhook) are IntaSend-specific, though refunds already
dispatch on `orders.payment_provider`. The
IntaSend payload shape and the Split Payments specifics (precision, sub-account KYC, payout
minimums/fees, settlement, refund-on-split) need confirming against a real account.

## PHASE 9 — Analytics + marketing: dashboard, discounts, customers

The seller Home screen has date-range metrics, a sales chart, order-status breakdown, top products, a
store-health/plan-usage card and a setup checklist. Discount codes (2026-10-03) live in `discounts`
(`20261003000100_discounts.sql`). `createOrder` prices them (`_shared/discounts.js`) and the
`orders_enforce_discount` trigger enforces usage limits at insert. The seller funds the discount, the
7% fee is on the discounted goods total, and a code that would put the order below CJ cost is refused.
Sellers manage codes and share their store link on `/seller/marketing`. `/seller/customers` derives
customer analytics from `store_customers` plus the store's orders. The dashboard converts each order
into the store's currency before summing, and shows sales by destination country. Not started:
free-shipping codes (owner call), collection/customer-group codes, automatic discounts, abandoned
cart, campaigns, customer tags/notes, analytics by device/conversion (nothing records sessions).

## PHASE 10 — Admin

Overview shows the platform financial model (seller GMV kept apart from Sellora's service-fee revenue
and subscription MRR/ARR, `TODO.md` §35), computed by `admin_platform_metrics()` in KES over every
paid order (`20261003000200_admin_platform.sql`), with refunds and 30-day seller churn. Tabs: Sellers,
Stores, Sync, Orders (with refunds), Plans, plus an Activity screen (audit log, app errors) off the
Overview. Seller suspension is `profiles.seller_status`. Store suspension is `stores.is_suspended`:
admin-only (guard trigger), it hides the store from `storefront_products`, and `createOrder` refuses
it. Not started: coupons, categories, themes, feature flags, platform settings, reports export,
support.

## PHASE 11 — Internationalization: first slice

`lib/core/i18n/`: KES/USD/GBP/EUR registry, a minor-unit `Money` type, and a country/shipping-zone/
payment-method registry mirroring `supabase/functions/_shared/regions.js` (`test/countries_test.dart`
fails on drift). `CurrencyService` converts from the server's `fx_rates`. Sellers pick shipping zones
in Customize store; checkout offers only in-zone countries. `flutter_localizations` is wired (English
only). `createOrder` enforces the store's zones (`storeShipsTo` in `_shared/regions.js`) and
refuses unconfigured countries. Strings are moving into `lib/l10n/app_en.arb` (`gen-l10n`, generated
code committed under `lib/l10n/generated/`): storefront, cart and buyer shell so far. Still open:
non-KES settlement, minor-unit persisted amounts, extracting the remaining screens, a second
language.

## PHASE 12 — Security + production

See `SELLORA_SECURITY_AUDIT.md`. Enforced in the database: RLS on every table, guard triggers on
`profiles` (no self-escalation), column-level grants hiding server-only order columns, append-only
`audit_logs`/`ledger_entries`, status-move/publishing/plan-limit triggers, per-user rate limits
(`consume_rate_limit`). Admin is `app_metadata.role`, set only by `supabase/scripts/grant-admin.js`.
`scripts/preflight.js` checks a rollout from outside.

Uncaught client errors are recorded in `client_errors` through the rate-limited
`report_client_error` (`lib/core/monitoring/error_reporter.dart`, release builds only), kept 30 days
by the `sellora-expire-client-errors` job. `docs/RUNBOOK.md` is the operations runbook.

Still open: `seller`/`buyer` is still the `profiles.role` column, not a JWT claim; a third-party
crash/uptime service; turning on PITR and creating a staging project (owner); the hosting decision
for `build/web`; untrack `functions/node_modules` (goes with deleting `functions/`).

## Decisions still required

1. Payment custody model: platform collect-and-disburse or per-seller IntaSend accounts.
2. CJ account ownership: shared by Sellora or connected per seller.
3. Which payment provider has confirmed marketplace/split-payment capability, and its
   refund/settlement rules (gates #1).
4. Are multi-store sellers required at launch?
5. Is `/s/:slug` accepted for MVP, with custom domains later?
