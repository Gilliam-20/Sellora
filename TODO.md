# SELLORA — MASTER BUILD PROMPT

## STATUS (as of 2026-10-03 — see WORKLOG.md and SELLORA_IMPLEMENTATION_PLAN.md for detail)

| Phase | Status |
|---|---|
| **0 — Audit** | Done. The Firebase-era audit is superseded by `SELLORA_SECURITY_AUDIT.md` |
| **1 — Foundation** | Done — theme, responsive shell, shared primitives, 0 analyzer issues |
| **2 — Auth + seller onboarding** | In progress — signup creates a store, marketing page is the signed-out entry point, seller shell now guards on store resolution. 2026-09-25: onboarding gained a store-setup step (name/category/country/currency) ahead of plan selection, the shell's no-store dead end now routes to it and creates the store, and email-verification status/resend is surfaced (not enforced). Still missing: multi-store switcher (blocked on open decision #4), required email verification, Google sign-in |
| **3 — Billing** | Security core done — server-side `subscribeSeller`, immutable billing ledger, locked-down subscription fields, configurable plan schema (orderLimit/storeLimit/features), listing usage tracked. 2026-09-26: order/store limits enforced server-side (audit §6, H6). Usage for listings, paid orders and stores comes from the server's `my_plan_usage()`. Renew action, billing history, plan limits shown side by side, and a downgrade that would exceed the new listing cap is refused, with a trigger backstop (audit §7). 2026-10-03 (§16): the launch plans are seeded by migration (Starter KES 1,300 / Growth 4,000 / Pro 10,300 with §16's limits), and Admin → Plans edits every field (prices, period, all three limits with "unlimited", support level, known features, internal feature flags, perks, popular badge, display order), creates plans and retires them (not sold to new sellers; current holders may renew). Database constraints bound every field. Plan cards everywhere list the configured limits and features instead of free-text perks, and a feature the app doesn't deliver yet shows as "coming soon". 2026-10-03 (§17): the Subscription & billing page. It shows status (active, ending, lapsed) with the paid-through date, usage meters with a nudge toward the cheapest plan with room once listings or orders reach 80%, a saved payment method (M-Pesa number or IntaSend's card page; no card is stored) plus the name and tax ID used on invoices, plans labelled Upgrade/Downgrade with what each one adds or removes, payments in progress with "Check payment", and history where each paid entry is a numbered invoice (INV-YYYY-NNNNNN) that downloads as a PDF. Billing now takes card payments as well as M-Pesa. Cancel marks the plan to end at period end and stops the renewal reminder (a daily job notifies 3 days before the end); resume undoes it, and paying again also clears it. Not done: gating anything on `features` (custom domain and advanced analytics don't exist as separate features yet), plans priced in a currency other than KES (owner call; IntaSend settles KES), automatic renewal (needs IntaSend recurring/tokenized payments, unverified), proration on a mid-period upgrade (owner call), emailed invoices and renewal reminders (in-app notification only) |
| **4 — Catalog + CJ import** | Client plumbing (endpoints, response parsing, admin sync) reconciled with the real CJ backend 2026-09-14; `ProductVariant` carries CJ's real per-SKU `vid`/`sku`/price 2026-09-15; a real seller import screen (variant picker + margin-based smart pricing + draft/publish) shipped 2026-09-15, replacing the old flat-price bottom sheet. Category browsing (chip filter), a shipping-cost estimate feeding the import screen's landed-cost pricing, and a buyer-facing variant selector all shipped 2026-09-18. 2026-09-26: product synchronization. The hourly `syncListings` job refreshes listed products' CJ cost and flags (and notifies the seller about) a listing whose price no longer covers cost plus fee, or that CJ no longer offers. It never unlists. The import screen's earnings readout now matches the real split (price − 7% fee − CJ cost; the buyer pays shipping). Listing ids are keyed `(store_id, id)` since the Supabase move, so the old doc-id concern is gone (audit §7). Still open: CJ integration is unverified against a real account; a server-side full `marginPricingService` quote remains a product call |
| **5 — Seller product management** | Listing/draft/unlist writes go to `products` (keyed `(store_id, id)`), gated by RLS plus the publishing and plan-limit triggers. Variants management UI (per-variant enable/disable + seller SKU override, from My Listings). Listings and the storefront read in pages. 2026-10-03 (§13): the import screen is a full editor: title, description (CJ's HTML cleaned to text), keep/drop images and pick the main one, per-variant on/off and SKU, tags (max 20) and SEO title/description with a search preview; `products.tags`/`seo_title`/`seo_description`, exposed on `storefront_products`. Still not started: collections (so no "assign collection" in the import editor), real inventory tracking, bulk operations, per-variant pricing, tag search on the storefront, editing tags/SEO after import |
| **6 — Store builder** | First slice: seller-facing "Customize store" screen editing `StoreModel`'s branding fields (name/tagline/logo/banner/accent color); storefront renders logo/banner/accent. Logo/banner upload to the `store-media` Storage bucket (2026-09-27). 2026-10-03 (§18): the store builder. A store's storefront is now a design document (Store → Theme → Sections → Blocks → Settings, `lib/data/models/store_design.dart`) that the storefront renders section by section instead of one fixed layout. It has theme settings (colors with palettes and a contrast warning, heading/body fonts from a vetted Google Fonts list, button shape, favicon), an announcement bar, a menu, homepage sections (hero, featured products: newest, best sellers or hand-picked; all products; collections; banners; testimonials; newsletter; text), and a footer with links and social profiles. Seller → Store design edits a draft beside a live desktop/phone preview made by the same renderer, then publishes it (`store_designs`, `publish_store_design()`, public `storefront_designs` view). Newsletter sign-ups are collected for the seller (`newsletter_subscribers`, rate-limited `subscribe_to_store_newsletter()`). "Customize store" is now "Store details" (name, tagline, logo, shipping zones). Not done: real collections (the collections section opens a product category), multiple themes (§19), product/cart pages in the store's theme, design version history beyond draft/live |
| **7 — Customer storefront** | Core shopping flow shipped 2026-09-20: the buyer shell (shop/cart/orders/alerts/profile) now lives at `/s/:slug` itself, guest-reachable end to end for browsing/cart, gated to a signed-in buyer only at checkout's submit step and for order history/profile. The old flat `/buyer` shell and its duplicate marketplace-era feed (`BuyerHomeController`) are deleted. Still not started: collections (needs PHASE 5's model first), a dedicated `Customer` model, order-detail/tracking, multi-store switcher |
| **8 — Payments + orders** | Done in code, never run live. `createOrder` prices each line from the seller's `products.sell_price`, snapshots buyer/seller/store and the 7% fee split; checkout offers M-Pesa and card (IntaSend); `intasendWebhook` confirms payment and pushes fulfillment to CJ, with cron retry and tracking refresh. 2026-10-03: admin refunds from the Orders tab (`ApiEndpoints.refundOrder`, admin-only `admin_order_refunds` view); checkout collects the structured address CJ ships to and `createOrder` refuses one without name/phone/street/city; checkout takes payment through an `OrderPaymentProvider` interface (IntaSend is the one implementation). Later on 2026-10-03 (§14/§15): seller order management. The Orders tab lists customer, date, total, payment and fulfilment state, items, shipping and channel, with filters (all/unpaid/paid/pending/processing/fulfilled/cancelled/refunded) and search; an order detail screen shows customer, lines, the payment and fee breakdown, CJ fulfilment state and tracking, and a timeline built from the audit log plus internal notes (`order_notes`, `order_timeline()`). Sellers can now cancel an unpaid order. The service fee rate is an admin setting (Admin → Plans, `app_config` `fees`, 0-30%, optional charge on shipping, audited); each order snapshots `service_fee_rate` and the new `service_fee_base`. Still open: multi-seller carts rejected, not split (owner call); no real split payout (needs a live IntaSend account); the server's payment routes are still IntaSend-specific; `payment_fee` is never filled (IntaSend's charge isn't read from the webhook yet); no "partially fulfilled" state (a CJ order ships as one parcel); sellers can't request a refund in-app |
| **9 — Analytics + marketing** | Dashboard-analytics slice shipped 2026-09-21: date-range filtering, gross sales/net revenue/AOV/order-status breakdown, a sales-over-time chart, top products, a store-health card (plan/listing/order usage), and a guided setup checklist. 2026-10-03: discount codes end to end (percentage/fixed, minimum order, specific products, dates, total and once-per-customer limits; priced and limit-checked server-side, the seller funds it, the fee is on what the buyer pays), a Customers screen (repeat rate, new customers, average spend, per-customer order history) and a Marketing screen (codes + shareable store link). Later on 2026-10-03: the dashboard converts each order into the store's currency before summing (it used to add KES and GBP totals together), and gained a sales-by-country card. Not done: free-shipping codes (owner call on who pays CJ freight), collection/customer-group codes (no models yet), automatic discounts, abandoned cart, email campaigns, customer tags/notes, analytics by device/conversion (nothing records sessions) |
| **10 — Admin** | First slice shipped 2026-09-22: Overview, Sellers, Stores, Sync, Orders and Plans tabs; Overview shows the platform financial model (seller GMV vs Sellora service-fee revenue vs subscription MRR/ARR, kept separate per §35). Seller suspension is `profiles.seller_status`. Refunds UI shipped 2026-10-03 (PHASE 8). Also 2026-10-03: Overview money figures come from `admin_platform_metrics()`, summed server-side in KES over every paid order (it used to sum the newest 200 orders' mixed-currency totals), plus refunds, ARR and 30-day seller churn. Per-store suspension (Stores tab; hides the catalog, closes checkout, the seller sees why). An Activity screen with the audit log and app errors. Not started: coupons, categories, themes, feature flags, platform settings, reports export, support |
| **11 — i18n** | First slice shipped 2026-09-25: `lib/core/i18n/` adds a KES/USD/GBP/EUR currency registry, an integer-minor-unit `Money` type, a country/shipping-zone/payment-method registry mirroring `supabase/functions/_shared/regions.js` (sync-tested), and `flutter_localizations` wiring. `CurrencyService` converts all four currencies from the server's `fx_rates` table; sellers pick shipping zones in Customize store; checkout offers only in-zone countries, converts CJ freight into the cart currency, and offers card (IntaSend hosted page) alongside Kenya-only M-Pesa. 2026-10-03: `createOrder` enforces the store's shipping zones server-side (and refuses unconfigured countries). ARB extraction started: `lib/l10n/app_en.arb` + `gen-l10n`, covering the storefront, cart and buyer shell. Not done: non-KES settlement, minor-unit persisted models, extracting the remaining screens, a second language |
| **12 — Security + production** | See `SELLORA_SECURITY_AUDIT.md` (2026-09-26, §6/§7). RLS on every table, `profiles` guard triggers (no self-escalation), column-level grants hiding server-only order columns, append-only `audit_logs`/`ledger_entries`, status/publishing/plan-limit triggers, Postgres-backed per-user rate limits (`consume_rate_limit`, 429). Admin is `app_metadata.role`, set only by `grant-admin.js`. 2026-10-03: uncaught app errors go to `client_errors` (rate-limited `report_client_error`, 30 days kept, Admin → Activity), and `docs/RUNBOOK.md` covers release order, rollback, secret rotation, backups/staging and incident triage. Still open: `seller`/`buyer` is the `profiles.role` column, not a JWT claim; a third-party crash/uptime service; turning on PITR and creating the staging project (owner); `functions/node_modules` tracked in git (goes with deleting `functions/`) |
| **Firebase → Supabase** | Done in code 2026-09-27. Phase 1 (2026-09-26): Auth + database (`supabase/migrations`, RLS replacing `firestore.rules`, `Supabase*Repository`, `grant-admin.js`). Phase 2 (2026-09-27): `functions/` ported to one `api` Edge Function (`supabase/functions/`), with pg_cron for the scheduled jobs, server-only order columns, catalog/config/rate-limit tables, Storage for store images, and the Android auth deep link plus an expired-link screen. 89 SQL/RLS checks (PGlite) and 261 Deno test steps pass. **Nothing is applied or deployed to the real project yet**: see the owner checklist below and WORKLOG.md 2026-09-27 |

Mock data was removed 2026-09-26. Every repository hits the real backend, so the catalog, checkout and
subscription payments work only once the `api` Edge Function is deployed with real CJ/IntaSend
secrets (owner steps below).

### Supabase migration — to do

**Owner (needs your Supabase dashboard / machine):**
- [ ] **Roll out the security hardening and the follow-up pass (2026-09-26, `SELLORA_SECURITY_AUDIT.md`
      §6 and §7), in this order:**
      1. `cd supabase && npx supabase db push`. This applies `20260928000000_security_hardening.sql`,
         `20260929000000_billing_usage.sql`, `20260930000000_listing_sync.sql`,
         `20260930000100_deployment_report.sql`, `20261003000000_admin_order_refunds.sql`,
         `20261003000100_discounts.sql`, `20261003000200_admin_platform.sql`,
         `20261003000300_orders_import_fees.sql`, `20261003000400_plan_config.sql` (which also
         seeds the Starter/Growth/Pro plans), `20261003000500_billing_page.sql` (cancel/resume,
         invoice numbers, saved payment method, and the `sellora-renewal-reminders` cron job) and
         `20261003000600_store_builder.sql` (store designs and newsletter sign-ups).
      2. `npm run deploy`: the new function calls `seller_order_gate`, which step 1 creates, and
         registers the `syncListings` job that step 1 schedules. Its `createOrder` also reads
         `stores.is_suspended`, calls `service_fee_settings()` and writes `service_fee_base`, so
         deploying it before step 1 would break every checkout. Its `subscribeSeller` also reads
         `subscription_plans.is_active`.
      3. `flutter build web` + `firebase deploy --only hosting`. The old build reads `products`
         directly, which buyers can no longer do, so storefronts are empty until this ships. It also
         calls the CJ catalog routes, which now refuse anyone but a signed-in seller or admin, and
         reads `my_plan_usage()`. The new build's checkout also sends the structured shipping
         address, which the new function requires, so deploy steps 2 and 3 together.
      4. `SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/preflight.js` (from
         `supabase/`). It checks everything below that can be checked from outside and names the
         fix for each failure, including approved sellers with no current subscription (their
         storefront shows nothing and checkout refuses their store). Re-run it after any change.
- [ ] Google Play Console → App content → Data safety: set the account-deletion URL to
      `https://<hosting domain>/#/delete-account`.
- [x] Put the project URL and **publishable** key (Settings → API) in
      `lib/core/config/supabase_config.dart`, or pass `--dart-define=SUPABASE_URL=...
      --dart-define=SUPABASE_PUBLISHABLE_KEY=...`. Never the service-role / secret key.
- [ ] Apply the schema: `cd supabase && npx supabase link --project-ref <ref> && npx supabase db push`.
      That applies every file in `supabase/migrations/`. If you use the SQL editor instead, paste
      them in filename order.
- [x] Authentication → Providers: make sure **Email** is enabled (confirmed 2026-09-26).
- [ ] Authentication → Sign In / Providers → Email: decide on **"Confirm email"**. **Off** matches the
      old Firebase behaviour, where users signed in right after sign-up. **On** means sign-up shows
      "check your inbox" first.
- [ ] Authentication → URL Configuration: set the **Site URL** (the web app's URL) and add these
      redirect URLs: the web app's URL(s), `http://localhost:*` for dev, and
      `sellora://auth-callback` for the Android app. Password-reset and confirmation links need them.
- [ ] Set the Edge Function secrets, then deploy it:
      `npx supabase secrets set CJ_API_KEY=... INTASEND_SECRET_KEY=... CRON_SECRET=<long random string>`
      then `cd supabase && npm run deploy`. Also set `INTASEND_WEBHOOK_CHALLENGE` to the challenge
      value you enter in IntaSend's webhook settings. It's technically optional, but it's what
      rejects a forged webhook before it costs a verification call; the webhook's per-IP limit can
      be spoofed (audit §7, N1). Optional: `ALLOWED_REDIRECT_ORIGINS` (comma-separated). Without it,
      payment redirects may only go to the `sellora-20.web.app`/`sellora.app` origins.
- [ ] Scheduled jobs: in the SQL editor, run
      `select vault.create_secret('https://<ref>.supabase.co/functions/v1/api', 'sellora_api_url');` and
      `select vault.create_secret('<the same CRON_SECRET>', 'sellora_cron_secret');`. pg_cron then runs
      FX refresh, catalog sync, fulfilment retry, tracking refresh, order expiry and the hourly
      listing sync (seven `sellora-*` jobs; `preflight.js` checks they all exist). Check them under
      Integrations → Cron. If pg_cron/pg_net weren't enabled when the migrations ran, enable them
      and re-run `20260927000100_scheduled_jobs.sql`, the `do $$` block at the end of
      `20260928000000_security_hardening.sql`, and the one at the end of
      `20260930000000_listing_sync.sql`.
- [ ] IntaSend dashboard: point the webhook at `https://<ref>.supabase.co/functions/v1/api/intasendWebhook`.
- [ ] Re-create the admin:
      `cd supabase && SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/grant-admin.js <admin email>`
      (run on a trusted machine; the service-role key bypasses RLS).
- [ ] Check the seeded plans in Admin → Plans (`20261003000400_plan_config.sql` inserts Starter,
      Growth and Pro at TODO §16's prices and limits; the USD reference prices of 10/31/80 are
      placeholders). Adjust anything there; re-running the migration never overwrites your edits.
- [ ] Set what the catalog sync mirrors: an `app_config` row with key `catalog` and value
      `{"sources": [{"categoryId": "...", "limit": 40}]}` (or `{"keyword": ...}`). Then run Admin →
      Sync once. Optionally add a `pricing` row to override the margin defaults in
      `supabase/functions/_shared/pricing.js`.
- [ ] Smoke-test in the running app: seller sign-up (store gets created) → onboarding → plan payment,
      buyer sign-up at `/s/<slug>`, checkout with M-Pesa sandbox, a small sandbox refund from Admin →
      Orders (confirms IntaSend's refund payload), logo upload in Customize store, a
      reset link on web and on Android, sign-out/sign-in, admin sign-in.
- [ ] Once happy: retire Firebase. Delete the deployed Cloud Functions (`firebase functions:delete`)
      and the `sellora-20` Auth/Firestore data, then delete `functions/`. It still holds an untracked
      `functions/.env` with live keys, so move anything you need first. Firebase stays only for
      Hosting until the hosting decision below.

**Code (can be done here):**
- [x] **Password-reset landing screen** (2026-09-26). `/reset-password` (`ResetPasswordView`).
- [x] **Android deep link for auth links** (2026-09-27). The `sellora://auth-callback` intent filter,
      plus `redirectTo`/`emailRedirectTo` on reset, sign-up and resend.
- [x] **Expired or used auth links** (2026-09-27). They land on `/auth-link-error`
      (`AuthLinkErrorView`), which covers wrong-device PKCE links too.
- [x] **Phase 2: port `functions/` to Supabase Edge Functions** (2026-09-27). One `api` function, with
      pg_cron jobs, `catalog_products`/`catalog_categories`, `app_config`, `cj_auth_tokens`,
      `rate_limits`, and the refund/fulfilment columns on `orders`. Not ported: PayPal and product
      reviews, neither of which the app called. App Check was also dropped (Firebase-only, report-only).
- [ ] Decide hosting for `build/web` (Supabase has none): keep Firebase Hosting, or move to
      Vercel/Netlify/Cloudflare Pages. Then update the Site URL above.
- [x] **Seller photo uploads → Supabase Storage** (2026-09-27). The `store-media` bucket, owner-only
      writes. Stores branded earlier keep their inline `data:` images until re-uploaded.

---

You are the lead Flutter architect, senior product engineer, UI/UX designer, backend engineer, and QA engineer responsible for transforming my existing Flutter application **Sellora** into a production-grade, Shopify-class ecommerce SaaS platform.

## 1. PRODUCT VISION

Sellora is a multi-tenant ecommerce SaaS platform inspired by the breadth and usability of Shopify.

The business model is:

1. Sellers create an account.
2. Sellers subscribe to a Sellora monthly plan.
3. Sellers create and customize their own online store.
4. Sellora provides a catalog of products sourced from CJ Dropshipping.
5. Sellers import products into their stores.
6. Sellora helps calculate recommended selling prices and margins.
7. Customers purchase products from seller stores.
8. Sellora processes the order.
9. CJ Dropshipping is used for product sourcing/fulfillment.
10. Sellora charges the seller a **7% service fee on successful product sales**.
11. Sellora also earns recurring subscription revenue.
12. Sellora should be designed for Kenya first but architected for international expansion.

The long-term vision is:

KENYA → AFRICA → GLOBAL

Do NOT build Sellora as merely a Kenyan shopping app.

Build it as a scalable commerce operating system for sellers.

---

# 2. MOST IMPORTANT RULE

DO NOT blindly rewrite the existing project.

First:

* inspect the entire existing codebase
* understand the current architecture
* identify existing working features
* identify reusable components
* identify technical debt
* identify incomplete screens
* identify existing Supabase integration
* identify existing authentication
* identify existing GetX controllers
* identify existing Dio/API services
* identify existing models
* identify existing navigation
* identify existing theme/design system
* identify existing CJ Dropshipping integration
* identify existing database schema
* identify existing storage/cache implementation

Then create a migration plan.

Preserve working code whenever possible.

Refactor only when necessary.

Do not destroy existing functionality merely to introduce a new architecture.

---

# 3. CURRENT TECHNOLOGY STACK

Use the existing project stack unless there is a strong technical reason to change it.

Primary stack:

* Flutter
* Dart
* GetX
* Dio
* Supabase
* Supabase Auth
* Supabase Postgres (RLS)
* Supabase Storage
* Supabase Edge Functions where appropriate
* GetStorage/local storage where already appropriate
* CJ Dropshipping API
* Responsive Flutter UI

The application must support:

* mobile
* tablet
* desktop
* Flutter Web where appropriate

Do not introduce unnecessary packages.

Before adding a package, determine whether the existing Flutter/Dart SDK supports it.

---

# 4. ARCHITECTURE

Use a scalable feature-first architecture.

Recommended structure:

lib/

app/
routes/
theme/
constants/
config/
bindings/
middleware/

core/
errors/
network/
supabase/
storage/
utils/
validators/
responsive/
widgets/

features/

```
authentication/
  data/
  models/
  repositories/
  services/
  controllers/
  views/
  widgets/

onboarding/

dashboard/

products/
  data/
  models/
  repositories/
  services/
  controllers/
  views/
  widgets/

catalog/

product_import/

orders/

customers/

analytics/

discounts/

marketing/

store/

storefront/

themes/

domains/

payments/

subscriptions/

billing/

shipping/

cj_dropshipping/

notifications/

settings/

support/

profile/

admin/
```

Use separation between:

UI
↓
GetX Controller
↓
Repository
↓
Service/API/Supabase
↓
Data source

Controllers must NOT contain large amounts of Supabase/Dio business logic.

Repositories should abstract data access.

Services should handle external integrations.

Models should represent domain data.

---

# 5. MULTI-TENANT ARCHITECTURE

This is extremely important.

Sellora is a SaaS platform.

One Sellora user may own one or multiple stores depending on subscription plan.

Every store-owned resource must be associated with:

* ownerId
* storeId

Do NOT create a flat database where all sellers share ambiguous product/order/customer data.

Recommended conceptual structure (implemented as Postgres tables keyed by store_id; see supabase/migrations):

users/{userId}

stores/{storeId}

stores/{storeId}/products/{productId}

stores/{storeId}/orders/{orderId}

stores/{storeId}/customers/{customerId}

stores/{storeId}/discounts/{discountId}

stores/{storeId}/collections/{collectionId}

stores/{storeId}/analytics/{document}

stores/{storeId}/settings/{document}

stores/{storeId}/domains/{domainId}

subscriptions/{subscriptionId}

cjProducts/{cjProductId}

platformOrders/{orderId}

payments/{paymentId}

notifications/{notificationId}

Use appropriate references and indexes.

Design RLS policies around ownership.

A seller must NEVER be able to read or modify another seller's:

* products
* orders
* customers
* store settings
* payments
* analytics
* subscription information
* private business information

---

# 6. SELLORA DESIGN SYSTEM

Create a professional design system before building all screens.

Sellora must NOT look like a random collection of Flutter screens.

Create reusable:

* AppScaffold
* ResponsiveScaffold
* Sidebar
* NavigationRail
* MobileNavigation
* TopBar
* PageHeader
* SectionHeader
* StatCard
* MetricCard
* DataTable
* ResponsiveDataTable
* SearchField
* FilterBar
* FilterChip
* PrimaryButton
* SecondaryButton
* DestructiveButton
* IconButton
* EmptyState
* LoadingState
* ErrorState
* ProductCard
* ProductGrid
* ProductListTile
* OrderStatusBadge
* PaymentStatusBadge
* StoreStatusBadge
* ConfirmationDialog
* BottomSheet
* AppSnackbar
* AppDrawer
* Pagination
* ImageUploader
* ProductImageGallery
* PriceField
* CurrencyField
* FormSection
* SettingsSection

Every reusable component must be responsive.

---

# 7. SELLORA VISUAL IDENTITY

Do not copy Shopify branding.

Sellora should have its own professional identity.

Primary brand color:

#FFC107

Use white and neutral colors as supporting colors.

For dark interfaces, use:

#303F9F

Create:

* light theme
* dark theme
* consistent typography
* consistent spacing
* consistent corner radius
* consistent elevation
* consistent iconography
* accessible contrast

The UI should feel:

* modern
* premium
* clean
* trustworthy
* simple
* business-focused
* professional

Avoid excessive gradients and unnecessary animations.

---

# 8. MAIN SELLER APPLICATION NAVIGATION

Create a Shopify-class seller admin experience.

Desktop sidebar:

1. Home
2. Orders
3. Products
4. Customers
5. Analytics
6. Marketing
7. Discounts
8. Online Store
9. Sales Channels
10. Apps / Integrations
11. Settings

Top bar:

* global search
* notifications
* store selector
* help/support
* account menu

Mobile:

Use a responsive navigation structure appropriate for small screens.

Do NOT simply squeeze desktop UI onto mobile.

---

# 9. DASHBOARD / HOME

Create a professional seller dashboard.

Display:

* Total sales
* Orders
* Average order value
* Products
* Customers
* Conversion rate
* Net sales
* Gross sales
* Refunds
* Pending orders
* Fulfillment status
* Top products
* Recent orders
* Sales chart
* Customer acquisition
* Store health
* Subscription status

Allow date ranges:

* Today
* Yesterday
* Last 7 days
* Last 30 days
* Last 90 days
* This year
* Custom

Include useful empty states for new sellers.

A new seller should receive a guided setup checklist:

[ ] Create store
[ ] Choose theme
[ ] Add domain
[ ] Import first product
[ ] Configure payment
[ ] Configure shipping
[ ] Publish store
[ ] Make first sale

---

# 10. PRODUCT SYSTEM

Build a complete product-management system.

Product list:

* search
* filters
* sorting
* pagination
* bulk selection
* bulk edit
* bulk delete
* product status
* inventory
* price
* compare-at price
* SKU
* vendor
* product type
* collections
* tags

Product creation/editing:

* title
* description
* images
* videos if supported
* pricing
* cost
* profit
* margin
* inventory
* SKU
* barcode
* variants
* options
* shipping
* SEO
* organization
* tags
* collections
* product status

Statuses:

* Draft
* Active
* Archived

---

# 11. CJ DROPSHIPPING CATALOG

This is one of Sellora's core differentiators.

Create a dedicated:

## Product Marketplace / CJ Catalog

Features:

* product search
* categories
* trending products
* recommended products
* product details
* CJ price
* shipping origin
* shipping destination
* shipping methods
* estimated delivery
* product variants
* supplier information
* images
* videos where available
* inventory availability

Seller can:

**Add to Store**

Before importing, show:

CJ cost
+
Shipping
+
Sellora/payment costs where appropriate
+
Recommended margin
==================

Recommended selling price

---

# 12. SMART PRICING ENGINE

Build a pricing engine.

Do NOT hard-code product prices.

Store configurable pricing rules.

Example:

Product cost:
KSh 1,000

Shipping:
KSh 300

Total landed cost:
KSh 1,300

Seller chooses target margin.

Example:

30%

System calculates recommended selling price.

Display:

Product cost
Shipping
Estimated fees
Recommended selling price
Estimated profit
Profit margin

Allow sellers to override the recommended price.

Admin should be able to configure default pricing rules.

The pricing engine must support:

* KES
* USD
* GBP
* EUR
* other currencies later

Do not assume KES everywhere.

---

# 13. PRODUCT IMPORT WORKFLOW

Seller clicks:

Import Product

Show an import editor.

Allow:

* change title
* edit description
* select images
* remove images
* edit variants
* edit price
* set margin
* edit SKU
* add tags
* assign collection
* optimize SEO
* publish immediately
* save as draft

Create an efficient:

CJ → Sellora Store

workflow.

---

# 14. ORDERS

Build a complete order management system.

Orders page:

* order number
* customer
* date
* total
* payment status
* fulfillment status
* items
* shipping
* channel

Filters:

* paid
* unpaid
* pending
* processing
* fulfilled
* partially fulfilled
* cancelled
* refunded

Order detail:

* customer information
* products
* variants
* payment
* shipping
* fulfillment
* timeline
* notes
* refund
* cancellation
* CJ fulfillment status

---

# 15. SUCCESSFUL ORDER SERVICE FEE

Sellora charges:

## 7% service fee per successful product sale

Apply this to the product/order subtotal.

Do NOT automatically charge the 7% on:

* shipping
* taxes

unless explicitly configured.

Example:

Product subtotal:
KSh 40,000

Sellora service fee:
7%

Sellora fee:
KSh 2,800

Record this transaction separately.

Create:

platformFee
serviceFeeRate
serviceFeeAmount
sellerRevenue
paymentFee
currency

Never modify historical fees when the admin changes the fee percentage.

The fee used for an order must be stored with that order.

---

# 16. SUBSCRIPTION SYSTEM

Initial plans:

STARTER

KSh 1,300/month

GROWTH

KSh 4,000/month

PRO

KSh 10,300/month

Create a subscription architecture where plans are configurable from the admin dashboard.

Do NOT hard-code plan limits throughout the application.

Plan configuration should include:

* price
* currency
* product limit
* order limit
* store limit
* custom domain
* analytics
* advanced features
* support level
* feature flags

Initial suggested limits:

Starter:

* 25 products
* 100 orders/month
* 1 store

Growth:

* 500 products
* 1,000 orders/month
* 3 stores

Pro:

* unlimited products
* unlimited orders
* 10 stores

These values must be configurable.

---

# 17. BILLING PAGE

Create a complete billing experience.

Show:

* current plan
* subscription status
* renewal date
* payment method
* billing history
* invoices
* usage
* product limit
* order usage
* store usage

Actions:

* upgrade
* downgrade
* cancel
* resume
* update payment method

Show upgrade benefits clearly.

---

# 18. STORE BUILDER

Create a professional no-code storefront builder.

Seller can customize:

* logo
* favicon
* colors
* typography
* homepage
* announcement bar
* navigation
* hero section
* featured products
* collections
* banners
* testimonials
* newsletter
* footer
* social links

Use reusable section-based architecture.

Concept:

Store
→ Theme
→ Sections
→ Blocks
→ Settings

Do not hard-code one storefront layout.

---

# 19. THEME SYSTEM

Create a theme architecture.

Theme model:

Theme

* id
* name
* version
* thumbnail
* sections
* settings
* typography
* colors

Allow multiple themes.

Initial themes:

* Minimal
* Modern
* Fashion
* Electronics
* General Store

The storefront renderer should dynamically render sections based on configuration.

---

# 20. STOREFRONT

Create a customer-facing storefront.

Pages:

* Home
* Shop
* Collections
* Product detail
* Search
* Cart
* Checkout
* Order confirmation
* Customer account
* Order history
* Contact
* About
* Privacy
* Terms
* Shipping policy
* Refund policy

Storefront must be independent from the seller admin interface.

---

# 21. CUSTOMER EXPERIENCE

Customer should be able to:

* browse products
* search
* filter
* sort
* view product
* choose variants
* add to cart
* update quantity
* checkout
* pay
* receive order confirmation
* track order
* create account
* view orders

Make checkout as simple as possible.

---

# 22. PAYMENTS

Design payment architecture as a provider abstraction.

Example:

PaymentProvider

Implement providers independently.

Kenya-first:

* M-Pesa
* Visa
* Mastercard

International:

* international card processing
* additional providers later

Do NOT tightly couple the entire application to IntaSend.

Payment architecture should allow providers to be added/replaced.

Never store raw card details.

Use provider-hosted/tokenized checkout where required.

Payment states:

* pending
* authorized
* paid
* failed
* refunded
* partially_refunded
* cancelled

---

# 23. SHIPPING

Create shipping architecture.

Seller settings:

* shipping zones
* shipping rates
* free shipping
* flat rate
* carrier-based shipping
* estimated delivery

Product/shipping logic should support:

Kenya
Africa
USA
UK
Global

Do not hard-code Kenya into the shipping engine.

---

# 24. CUSTOMERS

Customer management:

* customer list
* search
* filters
* customer profile
* order history
* total spent
* number of orders
* average order value
* customer tags
* notes
* marketing consent

---

# 25. ANALYTICS

Create:

Overview
Sales
Orders
Products
Customers
Marketing

Metrics:

* sales
* orders
* average order value
* conversion rate
* returning customers
* new customers
* top products
* top collections
* sales by country
* sales by device
* sales over time

Use clean charts.

Do not overload the dashboard.

---

# 26. MARKETING

Create marketing tools:

* discount codes
* automatic discounts
* campaigns
* abandoned cart
* email marketing architecture
* social sharing
* product promotion
* SEO tools

AI-ready architecture should allow future features such as:

* AI product descriptions
* AI ad copy
* AI social posts
* AI SEO optimization
* AI product recommendations

---

# 27. DISCOUNTS

Support:

* percentage discount
* fixed amount
* free shipping
* minimum purchase
* specific products
* collections
* customer groups
* start/end dates
* usage limits

---

# 28. SEO

Store-level SEO:

* meta title
* meta description
* social image
* favicon
* robots configuration
* sitemap architecture

Product SEO:

* SEO title
* meta description
* URL slug

Collection SEO:

same system.

---

# 29. DOMAINS

Create domain management.

Support architecture for:

* Sellora subdomain
* custom domain
* domain verification
* DNS instructions
* SSL status

Example:

mystore.sellora.com

Later:

[www.mystore.com](http://www.mystore.com)

---

# 30. SETTINGS

Create comprehensive settings.

Settings sections:

Store details
Payments
Checkout
Shipping
Taxes
Domains
Notifications
Customer accounts
Marketing
SEO
Policies
Staff/accounts
Billing
Security
Integrations

---

# 31. NOTIFICATIONS

Create notification center.

Events:

* new order
* payment received
* order fulfilled
* order cancelled
* refund
* subscription renewal
* subscription failed
* low inventory
* product imported
* CJ fulfillment update

Use a centralized notification model.

---

# 32. AUTHENTICATION

Support:

* email/password
* Google Sign-In where configured
* password reset
* email verification
* session handling
* logout

After authentication:

Determine:

* user
* seller profile
* subscription
* stores
* onboarding state

Then route appropriately.

---

# 33. ONBOARDING

New seller onboarding:

1. Welcome
2. Business/store name
3. Store category
4. Country
5. Currency
6. Choose plan
7. Create first store
8. Import first product
9. Configure payment
10. Configure shipping
11. Publish store

Make onboarding easy enough for someone who has never run an online store.

---

# 34. ADMIN PANEL

Build a separate platform-admin architecture.

Admin should be able to manage:

* users
* sellers
* stores
* subscriptions
* plans
* products
* CJ catalog
* orders
* platform fees
* payments
* refunds
* categories
* themes
* coupons
* reports
* support
* feature flags
* pricing rules
* platform settings

Admin analytics:

* total sellers
* active sellers
* new sellers
* churn
* MRR
* ARR
* GMV
* platform service-fee revenue
* subscription revenue
* orders
* customers
* conversion

---

# 35. PLATFORM FINANCIAL MODEL

Track separately:

Seller GMV

Sellora subscription revenue

Sellora service-fee revenue

Payment processing fees

Refunds

Chargebacks

CJ product cost

CJ shipping cost

Seller revenue

Platform revenue

Do NOT confuse seller GMV with Sellora revenue.

Example:

950 sellers

Average seller sales:
KSh 40,000/month

GMV:

KSh 38,000,000

7% Sellora service fee:

KSh 2,660,000

Subscription revenue using current plans:

Starter:
600 × KSh 999 = KSh 599,400

Growth:
300 × KSh 2,499 = KSh 749,700

Pro:
50 × KSh 4,999 = KSh 249,950

Total subscription revenue:

KSh 1,599,050

Total platform revenue:

KSh 2,359,050/month

This must be represented correctly in analytics.

---

# 36. CURRENCY ARCHITECTURE

Never assume one currency.

Every monetary model should contain:

amount
currency

Support:

KES
USD
GBP
EUR

Build currency conversion as a service.

Do not use floating-point arithmetic for financial calculations where avoidable.

Use integer minor units or a safe decimal strategy.

---

# 37. DATABASE SECURITY

Implement strict row-level security (RLS) policies.

Principles:

* authenticated users only where required
* store ownership verification
* role-based admin access
* seller isolation
* customer access limited to their own records
* server-side validation for financial operations
* clients must not be trusted with platform fee calculations
* subscription state should be validated server-side
* payment state must come from trusted payment callbacks/webhooks
* CJ credentials/tokens must never be exposed in the Flutter application

CJ credentials must be server-side.

---

# 38. CJ API SECURITY

Do NOT put sensitive CJ API credentials directly into Flutter.

Preferred architecture:

Flutter
↓
Sellora backend / Supabase Edge Function
↓
CJ Dropshipping API

Store secrets securely.

Implement:

* token management
* refresh logic where required
* rate limiting
* retry logic
* timeout handling
* logging
* error handling
* caching

---

# 39. NETWORK HANDLING

Improve the existing NetworkManager.

The app should handle:

online
offline
reconnecting
connection restored

Do not permanently redirect the user to an offline screen if the connection is temporarily unavailable.

When connectivity returns:

* retry appropriate operations
* refresh user data
* refresh store state
* refresh subscription
* refresh dashboard data

Avoid infinite retry loops.

---

# 40. ERROR HANDLING

Create centralized errors.

Handle:

* network errors
* Supabase errors
* authentication errors
* payment errors
* CJ errors
* validation errors
* permission errors
* unexpected errors

Give users useful messages.

Never expose internal stack traces to customers.

---

# 41. LOADING STATES

Every async screen must have:

* loading
* success
* empty
* error

Do not show blank screens while data loads.

Use skeleton loaders where appropriate.

---

# 42. RESPONSIVE DESIGN

Desktop:

* sidebar
* top navigation
* multi-column layouts
* data tables

Tablet:

* compact navigation
* adaptive grids
* responsive forms

Mobile:

* bottom navigation or drawer where appropriate
* stacked layouts
* mobile-friendly tables
* bottom sheets
* large touch targets

Use LayoutBuilder / MediaQuery / responsive utilities appropriately.

Do NOT create separate duplicated screens unnecessarily.

---

# 43. PERFORMANCE

Optimize for scale.

Avoid:

* unnecessary database reads
* unnecessary rebuilds
* huge widget trees
* loading entire collections into memory
* unbounded queries
* duplicate API calls

Use:

* pagination
* caching
* lazy loading
* query limits
* indexes
* debouncing
* image optimization
* efficient GetX updates

---

# 44. DATABASE DESIGN

Create proper database indexes.

Every important table should have clear ownership and query strategy.

Document:

* table purpose
* fields
* indexes
* security rules
* relationships

Do not create random rows just to make a screen work.

---

# 45. GETX RULES

Use GetX consistently.

Controllers should:

* expose observable state
* call repositories
* manage UI state
* coordinate workflows

Do not place huge amounts of business logic in widgets.

Avoid unnecessary Bindings.

The project should support straightforward dependency management with Get.put/Get.find where appropriate, while preventing duplicate controller instances.

---

# 46. ROUTING

Create centralized routes.

Example:

/login
/register
/onboarding
/home
/orders
/orders/:id
/products
/products/create
/products/:id
/catalog
/catalog/:id
/customers
/analytics
/marketing
/discounts
/store
/store/theme
/store/navigation
/settings
/billing

Storefront routes should be separate from seller-admin routes.

Use middleware for:

* authentication
* subscription
* admin
* onboarding

---

# 47. ACCESS CONTROL

Roles:

customer
seller
admin
support

Potential future roles:

staff
manager

Do not rely only on UI hiding.

Enforce authorization at backend/database level.

---

# 48. UX PRINCIPLES

Follow these principles throughout the entire application:

* simple
* obvious
* fast
* consistent
* minimal clicks
* clear hierarchy
* useful defaults
* helpful empty states
* meaningful feedback
* professional forms
* accessible controls

A beginner should understand the product without reading documentation.

---

# 49. IMPLEMENTATION STRATEGY

DO NOT attempt to build everything in one giant uncontrolled change.

Work in phases.

## PHASE 0 — AUDIT

Before modifying code:

1. inspect repository
2. inspect pubspec.yaml
3. inspect architecture
4. inspect routes
5. inspect Supabase
6. inspect database models
7. inspect controllers
8. inspect API services
9. inspect CJ integration
10. inspect existing UI
11. identify broken features
12. identify duplicated code

Then produce:

an architecture audit (now SELLORA_SECURITY_AUDIT.md)

and

SELLORA_IMPLEMENTATION_PLAN.md

Do not start massive feature implementation until this audit is complete.

---

# PHASE 1 — FOUNDATION

Implement:

* design system
* themes
* responsive framework
* navigation
* routing
* error handling
* loading states
* shared components
* architecture cleanup

Do not build advanced features yet.

---

# PHASE 2 — AUTH + SELLER ONBOARDING

Implement:

* authentication
* profile
* seller account
* subscription state
* onboarding
* store creation

---

# PHASE 3 — BILLING

Implement:

* Starter
* Growth
* Pro
* subscription UI
* billing history
* usage limits
* plan upgrades/downgrades

Make plan configuration data-driven.

---

# PHASE 4 — PRODUCT CATALOG + CJ

Implement:

* CJ catalog
* search
* categories
* product details
* shipping calculations
* smart pricing
* product import
* product synchronization

This is a major milestone.

---

# PHASE 5 — SELLER PRODUCT MANAGEMENT

Implement:

* products
* variants
* collections
* inventory
* pricing
* SEO
* bulk operations

---

# PHASE 6 — STORE BUILDER

Implement:

* themes
* sections
* blocks
* navigation
* homepage
* storefront renderer
* preview
* publish

---

# PHASE 7 — CUSTOMER STOREFRONT

Implement:

* storefront
* search
* collections
* product pages
* cart
* checkout
* customer account
* order tracking

---

# PHASE 8 — PAYMENTS + ORDERS

Status as of 2026-09-30: done in code, never run against a live IntaSend or CJ account. See the
STATUS table above and `SELLORA_IMPLEMENTATION_PLAN.md` PHASE 8 for what's still open.

---

# PHASE 9 — ANALYTICS + MARKETING

Implement:

* dashboard
* analytics
* discounts
* marketing
* customer analytics
* sales analytics

---

# PHASE 10 — ADMIN

Implement complete platform administration.

---

# PHASE 11 — INTERNATIONALIZATION

Implement:

* multi-currency
* country configuration
* shipping zones
* international payment architecture
* localization readiness

---

# PHASE 12 — SECURITY + PRODUCTION

Audit:

* RLS policies
* API security
* authentication
* payment security
* secrets
* rate limiting
* permissions
* data validation
* error handling
* performance

---

# 50. DEVELOPMENT RULE

At the end of EVERY phase:

1. Run flutter analyze.
2. Run tests.
3. Fix errors.
4. Verify affected screens.
5. Verify routing.
6. Verify Supabase operations.
7. Verify responsive layouts.
8. Document what changed.
9. Do not continue if the previous phase is broken.

Never leave the project in a knowingly broken state.

---

# 51. UI IMPLEMENTATION RULE

Before creating a new screen:

1. Define its purpose.
2. Define its user actions.
3. Define its data requirements.
4. Define loading state.
5. Define empty state.
6. Define error state.
7. Define desktop layout.
8. Define tablet layout.
9. Define mobile layout.
10. Define reusable components.

Then implement it.

---

# 52. SHOPIFY REFERENCE RULE

Use Shopify's current product experience as inspiration for:

* information architecture
* merchant workflows
* dashboard organization
* ecommerce terminology
* usability patterns
* feature completeness
* responsive behavior

But:

DO NOT copy Shopify's:

* branding
* logos
* proprietary assets
* exact visual design
* copyrighted text
* source code

Sellora must have its own visual identity.

---

# 53. FUTURE-READY FEATURES

Architect the system so these can be added later without major rewrites:

* AI store builder
* AI product descriptions
* AI advertisements
* AI product recommendations
* abandoned-cart recovery
* email campaigns
* SMS
* WhatsApp commerce
* affiliate marketing
* influencer tracking
* seller staff accounts
* multi-store management
* advanced shipping
* tax automation
* additional payment gateways
* additional supplier integrations
* Amazon-like marketplace capabilities
* mobile seller app
* public Sellora API

---

# 54. WHAT NOT TO DO

Do NOT:

* rebuild the entire application blindly
* hard-code business rules
* hard-code subscription prices
* hard-code currencies
* hard-code payment providers
* expose API secrets
* put all logic inside widgets
* create giant controllers
* create giant files
* duplicate mobile and desktop screens unnecessarily
* ignore database security (RLS)
* ignore empty states
* ignore error states
* create fake functionality
* use placeholder buttons that do nothing
* claim a feature works when it doesn't
* break existing working functionality

---

# 55. DEFINITION OF DONE

A feature is NOT complete just because its UI exists.

A feature is complete only when:

UI
+
State management
+
Validation
+
Repository
+
Backend
+
Database
+
Security
+
Error handling
+
Loading state
+
Empty state
+
Responsive layout
+
Testing

are implemented where applicable.

---

# 56. FIRST TASK

Do NOT immediately start coding all the features above.

Your FIRST task is:

## AUDIT THE EXISTING SELLORA PROJECT.

Inspect the complete project.

Then report:

### A. Existing architecture

### B. Existing features

### C. Existing screens

### D. Existing Supabase structure

### E. Existing RLS policies

### F. Existing CJ integration

### G. Existing payment integration

### H. Existing GetX architecture

### I. Existing navigation

### J. Existing reusable widgets

### K. Technical debt

### L. Missing features

### M. Recommended architecture

### N. Exact implementation phases

### O. Files that should be modified

### P. Files that should be created

Do not make massive changes during the audit.

After the audit, begin **PHASE 1**.

Work incrementally and keep the application compiling throughout the entire transformation.

The objective is not simply to create many screens.

The objective is to transform the existing Sellora codebase into a **production-ready, scalable, multi-tenant, Shopify-class commerce SaaS platform with its own identity.**
