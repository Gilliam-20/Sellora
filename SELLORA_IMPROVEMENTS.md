# Sellora — Improvements To Do

Compiled 2026-09-30 from a review of the codebase, `TODO.md`, `SELLORA_IMPLEMENTATION_PLAN.md` and
`SELLORA_SECURITY_AUDIT.md`. This list covers what is **not** done yet. For the Supabase rollout
steps themselves, follow the owner checklist in `TODO.md`.

**Current state in one line:** the security, pricing and payment logic is done in code (RLS on every
table, server-priced checkout, secrets kept in the Edge Function, append-only ledger and audit log),
but none of it has run against the real Supabase project, CJ Dropshipping or IntaSend.

---

## Top priorities (do these first, in order)

1. [ ] Staging project + end-to-end sandbox run (§1)
2. [ ] Full shipping address form (§3)
3. [ ] Buyer order detail / tracking page (§3)
4. [ ] Tests for checkout and product import (§3)
5. [ ] Image caching + offline handling (§4)

---

## 1. Go live safely (blocks everything else)

- [ ] Create a **separate staging Supabase project**. Run the `TODO.md` rollout there first:
      `db push` → `npm run deploy` → `node scripts/preflight.js`.
- [ ] Run a **real IntaSend sandbox payment** end to end (M-Pesa and card). Confirm the webhook payload
      shape, then make the payment amount check fail closed (audit M1).
- [ ] Run a **real CJ sandbox order** end to end. Confirm the auth handshake and response field names
      in `_shared/cjApi.js` / `cjAuth.js`.
- [ ] Smoke-test the full flow: seller sign-up → subscription payment → import CJ product → buyer
      checkout → CJ order → tracking.
- [ ] Turn on **Point-in-Time Recovery (PITR)** backups on the production database before real money
      moves.
- [ ] Decide hosting for `build/web` (keep Firebase Hosting or move to Vercel/Netlify/Cloudflare Pages).
- [ ] Retire Firebase: delete the deployed Cloud Functions and the Auth/Firestore data, then delete
      `functions/`. Rotate any key that was ever in `functions/.env`.

## 2. Architecture

- [ ] **CI with GitHub Actions** (there is no `.github/workflows` yet): `flutter analyze`,
      `flutter test`, `cd supabase && npm test`, and `db push` to staging when `supabase/migrations/`
      changes.
- [ ] **Split `supabase/functions/api/handler.ts` by domain** (orders, billing, catalog, webhooks,
      cron) behind one router. Keep it as one deployed function.
- [ ] **Monitoring and crash reporting:** Sentry for Flutter (`sentry_flutter`) and for the Deno
      function.
- [ ] **Alerts** for webhook failures and for orders stuck in `paid` but never pushed to CJ.
- [ ] Deployment **runbooks**: rollout, rollback, secret rotation, incident response.
- [ ] Close the open product decisions in `SELLORA_IMPLEMENTATION_PLAN.md`, starting with **#1,
      the payment custody model**. Payouts, refunds and tax all depend on it.

## 3. Must-fix app gaps

- [ ] **Full shipping address form and model.** `ShippingAddress` is only `{countryCode, line}`. CJ
      needs name, phone, line1/line2, city, region, postcode and country, so real orders will fail
      fulfilment.
- [ ] **Buyer order detail and tracking page.** Buyers can pay but can't see where their parcel is.
- [ ] **Refunds UI** plus an `ApiEndpoints` entry. The server-side `/refundOrder` already exists.
- [ ] **Controller tests for the money screens:** checkout, cart, product import pricing, seller
      subscription payment. Use the fakes in `test/fakes/`.
- [ ] Fix the known failing test in `seller_shell_controller_test.dart` (`NotificationCenter` not
      registered) so CI can require a green suite.

## 4. Relational database

Move the core data out of JSON columns and into real tables. Do this **before** real data exists,
while it's cheap. Each change goes in a new migration with checks in `supabase/tests/rls.test.mjs`.

- [ ] `orders.items jsonb` → **`order_items`** table (order_id, product_id, variant_id, qty,
      unit_price, supplier_cost, fee). Needed for per-product reports, partial refunds and splitting
      multi-seller carts.
- [ ] `products.variants jsonb` → **`product_variants`** table (product_id, cj_vid, sku, price,
      enabled). Unblocks per-variant pricing, inventory and bulk edits.
- [ ] `orders.refunds jsonb` → **`refunds`** table referencing `order_items`, with matching
      `ledger_entries`.
- [ ] `orders.shipping_address jsonb` → **`addresses`** table with CJ's full field set.
- [ ] Money as **integer minor units** (`bigint amount_minor` + `currency char(3)`) instead of
      `numeric(12,2)`, matching the Dart `Money` type.
- [ ] `CHECK` on the store slug format and a unique index on `lower(slug)`.
- [ ] Indexes on the columns RLS filters by: `store_id`, `seller_id`, `buyer_id`, `created_at desc`.
- [ ] Run Supabase's security and performance advisors once the project is live.

## 5. Payments

- [ ] **Payment-provider layer** in `_shared/` (`createCharge` / `verify` / `refund`), with IntaSend
      as the first implementation. Leaves room for Paystack or Flutterwave (Africa) and Stripe
      (global).
- [ ] **M-Pesa STK push as the default in Kenya.** Keep the hosted card page as the fallback.
- [ ] **Subscription auto-renewal and cancel/resume.** Today unpaid plans simply lapse. Send renewal
      reminders at 3 days and 1 day out; use M-Pesa Ratiba or saved-card billing where supported.
- [ ] **Seller earnings and payouts screen** ("pending / available / paid out") built on
      `ledger_entries`.
- [ ] **Idempotency key on `createOrder`** so a double-tap on a slow network can't create two orders.
- [ ] Split multi-seller carts instead of rejecting them.
- [ ] Decide on proration for a mid-period plan upgrade.

## 6. Security

- [ ] Move the **buyer/seller role into the JWT** (`app_metadata` or a custom access-token hook),
      like admin already is. It's still read from the `profiles.role` column.
- [ ] **Multi-factor sign-in (TOTP) for admin**, later for sellers.
- [ ] **Require email verification** before a seller can list products or receive payouts.
- [ ] Make `INTASEND_WEBHOOK_CHALLENGE` **required**, not optional.
- [ ] Turn on Supabase Auth **leaked-password protection** and **CAPTCHA** on sign-up and password
      reset.
- [ ] **Rotate secrets** on a schedule and after launch.
- [ ] **External penetration test** before expanding beyond Kenya.
- [ ] Untrack `functions/node_modules` (goes with deleting `functions/`).

## 7. User experience

- [ ] **Image caching** with `cached_network_image` and sized thumbnails (matters on Kenyan mobile
      data).
- [ ] **Offline and slow-network handling** with `connectivity_plus`: offline banner, retry buttons,
      keep the cart if the connection drops mid-checkout.
- [ ] **Skeleton loaders and pull-to-refresh** on every list (only 9 screens have
      `RefreshIndicator`).
- [ ] **Accessibility:** `Semantics` labels on icon buttons, product cards and `ManifestStub` (there
      are none today).
- [ ] **Translations:** move the ~179 hard-coded `Text('...')` strings into ARB files; add Swahili.
- [ ] **Google sign-in** to reduce sign-up friction.

## 8. Seller features ("Shopify-class")

- [ ] Collections.
- [ ] Discount codes.
- [ ] Bulk product edit.
- [ ] Real inventory tracking and per-variant pricing.
- [ ] Seller alerts (push and email): new order, low margin (the sync job already flags these), plan
      about to expire.
- [ ] Store builder: themes, sections, preview before publishing (Phase 6 only has branding).
- [ ] Multi-store switcher (blocked on open decision #4).
- [ ] Custom domains for storefronts (after `/s/:slug`).
- [ ] **SEO and shareable links:** preview metadata (Open Graph tags) at minimum, ideally pre-rendered
      product pages, since search engines don't index Flutter web.
- [ ] Customer analytics and a dedicated `Customer` model.

## 9. Admin

- [ ] Per-store suspension.
- [ ] Refunds UI.
- [ ] Coupons, categories, feature flags, platform settings.
- [ ] Reports, support tools, churn tracking.

## 10. Code health

- [ ] Split the largest screens into smaller widgets: `marketing_view.dart` (865 lines),
      `seller_dashboard_view.dart` (608), `seller_onboarding_view.dart` (549),
      `product_import_view.dart` (529).
- [ ] Keep `flutter analyze` at 0 issues and enforce it in CI.
