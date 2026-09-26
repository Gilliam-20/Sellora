# Sellora

A subscription marketplace: sellers pay a monthly fee to list products
sourced from **CJ Dropshipping**, buyers shop the combined catalog
across every seller, and payments (subscriptions + checkout) run
through **IntaSend** and **M-Pesa**. One Flutter codebase targets Web,
Android and iOS, with three role-based portals — Buyer, Seller, Admin —
behind a single sign-in.

## Running it — there is no demo mode

Every repository talks to the real backend; the in-memory mock mode
(`AppConstants.useMockData`) was removed on 2026-09-26. You need a
reachable Supabase project (`lib/core/config/supabase_config.dart`) with
`supabase/migrations` applied. Sign-in/sign-up work against that alone.
The catalog, CJ import, checkout and subscription payments also need the
`api` Supabase Edge Function deployed with real CJ Dropshipping and
IntaSend credentials; until then those screens show errors or empty
states. See WORKLOG.md and TODO.md's Supabase checklist.

This zip contains the Dart source (`lib/`) and `pubspec.yaml` only —
platform runner folders (`android/`, `ios/`, `web/`, etc.) aren't
included, so the first step scaffolds them:

```bash
flutter create . --org com.yourcompany.sellora --project-name sellora
flutter pub get
flutter run
```

`flutter create .` is safe to run on top of existing code — it only
adds the platform folders that are missing; it won't touch `lib/` or
`pubspec.yaml`.

## Architecture

Strict **View → Controller → Repository**, GetX throughout:

```
lib/
  app/
    theme/          the Meridian design system (see below)
    routes/         route names, GetPage table, role-based middleware
    bindings/        InitialBinding — permanent, app-wide singletons
  core/
    network/        DioClient (auto-attaches Firebase ID token)
    widgets/        signature components (ManifestStub, ProductCard...)
    utils/          validators, formatters
  data/
    models/         plain Dart models, no Firestore/UI leakage
    services/       thin wrappers: Firebase Auth, Firestore, CJ proxy, IntaSend proxy
    repositories/   ONE abstract interface per domain, with a
                    Supabase-backed impl (in-memory test fakes live in test/fakes/)
  modules/
    auth/ onboarding/ buyer/ seller/ admin/
      views/  controllers/  bindings/   (per-route, lazyPut)
```

- **InitialBinding** (`lib/app/bindings/initial_binding.dart`) registers
  every service and repository once, as permanent singletons, always
  the real Supabase-backed implementations.
- Every route's own `Bindings` class `Get.lazyPut`s its controller(s),
  so a controller is created when its page is pushed and disposed when
  popped.
- `RoleMiddleware` (`lib/app/routes/role_middleware.dart`) guards the
  buyer/seller/admin shells — a signed-in buyer is redirected away from
  `/seller`, an unsubscribed seller is redirected to onboarding instead
  of their dashboard, etc.

## The Meridian design system

Named, not default-Material:

- **Colors** (`lib/app/theme/app_colors.dart`) — Cargo Navy (trust,
  logistics), Manifest Gold (seller CTAs / entrepreneurial energy),
  Horizon Teal (buyer confirmations), on cool neutrals (Ink / Mist /
  Slate) rather than a generic warm cream.
- **Type** (`lib/app/theme/app_typography.dart`) — "Cargo" (Fraunces)
  for headline/hero moments only, "Ledger" (Inter) for all UI chrome
  and data. Loaded via `google_fonts`; see the commented-out `fonts:`
  block in `pubspec.yaml` if you'd rather bundle them locally.
- **Signature components** (`lib/core/widgets/`) — `ManifestStub`, a
  cargo-tag-styled card (flat left edge + color bar) used for every
  order/stat instead of a generic uniform rounded card; `ProductCard`
  for the storefront grid.

## Wiring up the real backend

Everything below is scaffolded and ready — you're filling in
credentials and endpoints, not writing new architecture.

### 1. Supabase

Everything runs on one Supabase project: Auth, Postgres (schema and RLS in
`supabase/migrations/`), Storage (store images) and the `api` Edge
Function. From `supabase/`:

```bash
npm install
npm test                                   # schema/RLS checks + function tests, no Docker needed
npx supabase link --project-ref <ref>      # once
npx supabase db push                       # apply the migrations
```

Put the project URL and publishable key in
`lib/core/config/supabase_config.dart` (or pass them with `--dart-define`).
In the dashboard, set the Site URL and add the redirect URLs auth emails
need: the web app's URL(s), `http://localhost:*` for development, and
`sellora://auth-callback` for Android.

### 2. The `api` Edge Function (CJ Dropshipping + IntaSend proxies)

The Flutter app **never** talks to CJ Dropshipping or IntaSend
directly — it calls `supabase/functions/api` (`ApiEndpoints`), which holds
the real secret keys server-side. This is the difference between "a secret
key baked into an APK anyone can decompile" and "a secret key that
never leaves your server."

```bash
npx supabase secrets set CJ_API_KEY=... INTASEND_SECRET_KEY=... CRON_SECRET=<long random string>
# optional: INTASEND_WEBHOOK_CHALLENGE=... (enforced when set), ALLOWED_REDIRECT_ORIGINS=https://a,https://b
npm run deploy
```

Then register the scheduled jobs' target in Vault (SQL editor):

```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1/api', 'sellora_api_url');
select vault.create_secret('<the same CRON_SECRET>', 'sellora_cron_secret');
```

Point IntaSend's webhook (dashboard → Webhooks) at
`https://<ref>.supabase.co/functions/v1/api/intasendWebhook`. The webhook is
implemented from IntaSend's published docs, not tested against a real
account, so reconfirm the payload shape before going live.

Create the admin with `node scripts/grant-admin.js <email>` (needs
`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; run it on a trusted
machine).

### 3. Subscription plans

Seed the `subscription_plans` table with your real pricing — or sign in
as admin and use the **Plans** tab. Onboarding's plan step is empty
until at least one plan exists.

## Platforms

Flutter Web + Android + iOS from one codebase. Supabase has no static
hosting, so the web build still deploys to Firebase Hosting until that's
decided — `firebase.json` points hosting at `build/web`:

```bash
flutter build web
firebase deploy --only hosting
```

## What's a starting point vs. production-ready

Built out and demoable end-to-end: auth (buyer/seller sign-up +
sign-in), seller onboarding with plan selection and M-Pesa payment,
seller catalog browsing + listing, seller order fulfillment queue,
seller subscription management, buyer storefront/cart/checkout/order
history, and the full admin panel (sellers, catalog sync, orders,
plans).

Order pricing/creation and payment confirmation are server-side
(`createOrder` and `intasendWebhook` in `supabase/functions/api/handler.ts`),
and RLS doesn't let a client write an order or grant themselves a role.
Still worth hardening before real money moves through it:
- IntaSend's webhook "challenge" verification is implemented from their
  published docs, not tested against a real account — reconfirm the exact
  payload shape before going live.
- The current checkout flow assumes one seller per cart; a real
  multi-seller cart is rejected rather than split into one order per
  seller.
- Admin is an `app_metadata` claim, but `seller`/`buyer` still live on the
  `profiles.role` column rather than a signed auth token (guard triggers
  stop a user changing it).
- CJ Dropshipping's real API auth handshake and response shapes vary by
  account type — `supabase/functions/_shared/cjApi.js` sketches the flow;
  confirm field names against your CJ developer account before going live.
- Subscription billing goes through the server (`subscribeSeller`), and
  only a confirmed payment activates a plan — but, like checkout, it has
  never run against a live IntaSend account.
