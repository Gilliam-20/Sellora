# Sellora

A subscription marketplace: sellers pay a monthly fee to list products
sourced from **CJ Dropshipping**, buyers shop the combined catalog
across every seller, and payments (subscriptions + checkout) run
through **IntaSend** and **M-Pesa**. One Flutter codebase targets Web,
Android and iOS, with three role-based portals — Buyer, Seller, Admin —
behind a single sign-in.

## Try it in 60 seconds — no backend required

The app ships with `AppConstants.useMockData = true`
(`lib/core/constants/app_constants.dart`), which swaps every repository
for an in-memory mock implementation with sample CJ-style products and
plans. No Firebase project, IntaSend account, or CJ Dropshipping key
needed to click through every screen.

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

On the sign-in screen, use any password (8+ characters) and an email
containing:

| Email contains | Signs you in as |
|---|---|
| `seller` | Seller portal, active subscription, a starter storefront |
| `admin`  | Admin portal |
| anything else | Buyer portal |

Example: `seller@demo.com` / `password123`.

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
    repositories/   ONE abstract interface per domain, with both a
                    Firebase-backed impl and a mock impl (data/repositories/mock/)
    mock/           sample seed data used by the mock repositories
  modules/
    auth/ onboarding/ buyer/ seller/ admin/
      views/  controllers/  bindings/   (per-route, lazyPut)
```

- **InitialBinding** (`lib/app/bindings/initial_binding.dart`) registers
  every service and repository once, as permanent singletons. Which
  repository implementation gets bound — mock or Firebase — is decided
  by a single flag: `AppConstants.useMockData`.
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

### 1. Firebase

```bash
npm install -g firebase-tools
firebase login
flutterfire configure   # generates lib/firebase_options.dart
```

Then in `lib/main.dart`, uncomment the `Firebase.initializeApp(...)`
block and its imports, and in
`lib/core/constants/app_constants.dart` set:

```dart
static const bool useMockData = false;
```

Deploy Firestore rules/indexes:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

### 2. Cloud Functions (CJ Dropshipping + IntaSend proxies)

The Flutter app **never** talks to CJ Dropshipping or IntaSend
directly — it calls your own Cloud Functions
(`functions/src/cj.ts`, `functions/src/intasend.ts`), which hold the
real secret keys server-side. This is the difference between "a secret
key baked into an APK anyone can decompile" and "a secret key that
never leaves your server."

Credentials are Cloud Secret Manager secrets (not `functions:config:set`,
which is deprecated), set once per environment:

```bash
cd functions
npm install
firebase functions:secrets:set CJ_EMAIL
firebase functions:secrets:set CJ_PASSWORD
firebase functions:secrets:set INTASEND_SECRET_KEY
firebase functions:secrets:set INTASEND_WEBHOOK_CHALLENGE   # any random string; you'll enter the same value in IntaSend's dashboard below
npm run deploy
```

`INTASEND_ENV` (`"sandbox"` or `"live"`) is a plain runtime env var, not a
secret — set it in `functions/.env` (`INTASEND_ENV=sandbox`) rather than
via `secrets:set`.

Update `lib/core/constants/app_constants.dart`'s
`ApiEndpoints.baseFunctionsUrl` with your deployed functions URL.

Configure IntaSend's webhook (dashboard → Webhooks) to point at your
deployed `intasendWebhook` function, with the same challenge string you
set as `INTASEND_WEBHOOK_CHALLENGE` above — `intasendWebhook` verifies it
before confirming any payment, and reconfirm the exact webhook payload
shape against IntaSend's current docs before going live; it's implemented
from their published docs, not tested against a real account.

### 3. Subscription plans

Seed `subscription_plans` in Firestore with your real pricing (the
mock `Starter` / `Growth` / `Scale` tiers in
`lib/data/mock/mock_seed_data.dart` are placeholders) — or sign in as
admin and use the **Plans** tab, which edits Firestore directly.

## Platforms

Flutter Web + Android + iOS from one codebase. For Web, `firebase.json`
already points hosting at `build/web`:

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

As of 2026-09-11, order pricing/creation and payment confirmation are
server-side (`functions/src/orders.ts`'s `createOrder`, `functions/src/
intasend.ts`'s `intasendWebhook`), and `firestore.rules` no longer lets a
client write an order directly or grant themselves a role. Still worth
hardening before real money moves through it:
- IntaSend's webhook "challenge" verification is implemented from their
  published docs, not tested against a real account — reconfirm the exact
  payload shape before going live.
- The current checkout flow assumes one seller per cart; a real
  multi-seller cart is rejected rather than split into one order per
  seller.
- Custom claims (Firebase Auth) for `role`/`admin` — the Firestore rules
  no longer let a user grant themselves a role, but `role` still lives on
  a plain Firestore document rather than a signed auth token.
- CJ Dropshipping's real API auth handshake and response shapes vary by
  account type — `functions/src/cj.ts` sketches the flow; confirm field
  names against your CJ developer account before going live.
- Subscription billing (`FirebaseSubscriptionRepository.subscribeSeller`)
  still writes `billing_history` directly from the client, which
  `firestore.rules` already silently blocks against real Firestore — the
  same class of fix `createOrder` just got, not yet done for billing.
