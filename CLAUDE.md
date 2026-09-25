# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Flutter app

```bash
flutter pub get
flutter run                 # device/emulator
flutter run -d chrome       # web
flutter analyze             # lint — analysis_options.yaml adds prefer_single_quotes,
                            # always_declare_return_types, avoid_print, sort_child_properties_last
dart format lib
flutter build web           # output lands in build/web, where firebase.json's hosting points
```

There is **no `test/` directory and no test suite yet**. `flutter_test` is a dev dependency, so
once tests exist the usual commands apply — `flutter test`, a single file with
`flutter test test/foo_test.dart`, a single case with `--plain-name 'description'`.

Only `android/` and `web/` platform folders exist; there is no `ios/`. Run
`flutter create . --org com.yourcompany.sellora --project-name sellora` to scaffold what's
missing — it only adds absent platform folders and won't touch `lib/` or `pubspec.yaml`.

### Cloud Functions

```bash
cd functions
npm install
npm run build     # no-op — plain JS, no compile step
npm test          # node --test test/
npm run serve     # firebase emulators:start --only functions,firestore
npm run deploy    # firebase deploy --only functions
npm run logs
```

As of 2026-09-12 `functions/` is plain JavaScript (no TypeScript, no `tsconfig.json`) — see
`WORKLOG.md`'s 2026-09-12 entry for why. `npm run build` stays as a no-op purely because
`firebase.json`'s `predeploy` hook still calls it.

### Supabase (Auth + Postgres, since 2026-09-26)

```bash
cd supabase
npm install
npm test          # migrations + RLS checks in PGlite (no Docker), then grant-admin tests
npx supabase link --project-ref <ref>   # once
npx supabase db push                    # apply supabase/migrations to the linked project
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/grant-admin.js admin@example.com
```

The app reads its project URL and publishable key from `lib/core/config/supabase_config.dart`
(`--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...` overrides). Any schema
or policy change goes in a **new** migration file, with a matching check in
`supabase/tests/rls.test.mjs`.

### Firebase (what remains: Cloud Functions + hosting, until phase 2)

```bash
firebase deploy --only hosting
```

## Architecture

### The mock/real switch is the central design fact — except identity

`AppConstants.useMockData` (`lib/core/constants/app_constants.dart`) is a single `const bool` that
decides which repository implementations `InitialBinding` binds for the catalog, orders,
notifications, subscriptions, admin and FX rates. When `true` those run on in-memory mocks — no CJ
Dropshipping key or IntaSend account required.

**`AuthRepository` and `StoreRepository` are the one exception** (as of 2026-09-25, see `WORKLOG.md`):
`InitialBinding` always binds `SupabaseAuthRepository`/`SupabaseStoreRepository`, regardless of
`useMockData`, and `lib/main.dart` always calls `Supabase.initialize()`. `MockAuthRepository`/
`MockStoreRepository` still exist and are exercised by `test/auth_repository_test.dart` and
`test/admin_dashboard_controller_test.dart`, but nothing in the running app binds them anymore. This
means running the app at all — even with `useMockData = true` — requires a reachable Supabase project
(`SupabaseConfig`) with `supabase/migrations` applied; sign-in/sign-up will fail without it.
One direct consequence: the two demo storefronts `MockProductRepository`/`MockSeedData` seed
(`aminas-picks`, `jengo-electronics`) are no longer reachable by browsing, since `StoreRepository`
reads the real (likely empty) `stores` table rather than that seed data — only a real signed-up
seller's own store resolves.

**Firebase → Supabase is half done** (see `WORKLOG.md`, 2026-09-26). Phase 1 moved Auth and the
database: `supabase/migrations/` holds the schema, and its RLS policies/guard triggers replace
`firestore.rules`. Sign-up creates the profile (and a seller's store) in the `handle_new_user`
trigger, not from the client. Phase 2 has not started: `functions/` is still Firebase Cloud Functions,
still verifies Firebase ID tokens, and still reads/writes Firestore. The app now sends Supabase tokens,
so every `ApiEndpoints` call fails until the port to Edge Functions lands. That's harmless only while
`useMockData` is true.

Everything else in `functions/` (plain JS — see the Cloud Functions section above) and the non-identity
`Supabase*Repository` classes should still be treated as scaffolded-but-unexercised:
**the app has never run its catalog/order/payment flows against a real backend**, only identity.

The consequence for any change: **every repository is an abstract interface with two implementations**
— a `Supabase*` one in `lib/data/repositories/` and a mock in `lib/data/repositories/mock/`. Adding a
repository method means implementing it in both, or demo mode breaks. `CartRepository` is the single
deliberate exception (in-memory either way, so one implementation).

### View → Controller → Repository, via GetX

Dependency lifetime is split across exactly two places:

- `lib/app/bindings/initial_binding.dart` registers every service and repository once, as
  `permanent: true`. Nothing else registers app-wide singletons.
- Each route's own `Bindings` class `Get.lazyPut`s its controllers, so a controller is constructed
  when its page is pushed and disposed when popped.

Models in `lib/data/models/` are plain Dart with camelCase `fromMap`/`toMap` — no backend types and
no Flutter imports leak into them. `SupabaseService` (`lib/data/services/supabase_service.dart`)
exists so repositories never hold raw table names. Its `toRow`/`fromRow` translate model maps to
snake_case columns and fix up timestamp offsets. Always go through them rather than passing
`toMap()` to the client directly.

### Secrets live in Cloud Functions, never in the app

The Flutter app never calls CJ Dropshipping or IntaSend directly. It calls Sellora's own Cloud
Functions (`ApiEndpoints` in `app_constants.dart`), which hold the real keys server-side.
`DioClient` (`lib/core/network/dio_client.dart`) attaches the Supabase access token (JWT) to every
request. The backend's auth check verifies it (today `verifyAuth` in `functions/index.js`, which
still expects a Firebase ID token until phase 2) and is the only thing between the open internet
and the CJ/IntaSend secret keys. Any new proxy function must call it first.

`functions/src/` currently authenticates with **one platform-level credential per provider**
(`functions.config().cj`, `functions.config().intasend`) — not per seller. Note also that
`functions.config()` is deprecated in newer firebase-functions versions and needs moving to
`defineSecret`/params.

### Role-based routing

`lib/app/routes/app_pages.dart` holds a flat `GetPage` table; `RoleMiddleware` guards the
buyer/seller/admin shells and additionally redirects a seller without an active subscription to
onboarding rather than the dashboard. Routing is hash-based (no `usePathUrlStrategy()` call), though
`firebase.json` already rewrites `**` to `/index.html`.

### The Meridian design system

Named and deliberate, not default Material — `lib/app/theme/`. Cargo Navy (trust/logistics),
Manifest Gold (seller CTAs), Horizon Teal (buyer confirmations) on cool Ink/Mist/Slate neutrals.
Type is Fraunces ("Cargo") for headlines only and Inter ("Ledger") for all UI chrome and data, loaded
via `google_fonts`. `ManifestStub` (`lib/core/widgets/`) is the signature component — a cargo-tag card
with a flat left edge and a color bar, used for every order and stat instead of a uniform rounded
card. Prefer extending these over introducing new one-off colors, type styles, or card treatments.

## In-flight architectural change

The app is being reshaped **from a shared marketplace into a Shopify-style multi-tenant platform**:
each seller gets their own storefront at `sellora.app/s/{slug}`, buyers become customers of a specific
store rather than global Sellora accounts, and the shared buyer feed goes away.

The design is written up — see `WORKLOG.md` for the decisions, the open questions, and a link to the
full document. As of 2026-09-11, implementation has started on decisions that don't require the still-
open questions (#1 buyer account scoping, #4 multi-store-per-seller, #5 white-label depth): a
`StoreScope` service resolves `/s/:slug`, `stores/{storeId}/products` and `.../orders` subcollections
now exist with matching Firestore rules, and `SELLORA_ARCHITECTURE.md`/`SELLORA_IMPLEMENTATION_PLAN.md`
hold the current audit and phased plan. The buyer marketplace in `lib/modules/buyer/` and the flat
top-level `listings`/`orders` collections are still live and have **not** been migrated or removed —
check `WORKLOG.md`'s latest entry before extending either the old or new model.

## Known gaps (from README, still open)

As of 2026-09-11, order creation is server-side and the IntaSend webhook verifies a shared "challenge"
value before confirming payment — see `WORKLOG.md`'s 2026-09-11 entry for what changed and why. Still
open:

- The IntaSend webhook "challenge" scheme in `functions/src/intasend.ts` is implemented from their
  published docs, not verified against a real account — reconfirm the exact payload shape before going
  live.
- Admin is `app_metadata.role` only: one dedicated email, provisioned solely by
  `supabase/scripts/grant-admin.js` (no in-app admin sign-up). The `seller`/`buyer` distinction
  in RLS still reads `profiles.role`. Self-escalation is blocked by the sign-up trigger and
  `profiles_guard_update`, but it's still a table column, not a JWT claim.
- The current checkout assumes one seller per cart — `createOrder` now rejects a mixed-seller cart
  outright rather than silently misattributing it, but doesn't split it either.
- CJ Dropshipping's auth handshake and response shapes vary by account type; `functions/src/cj.ts`
  sketches the flow but field names need confirming against a real CJ developer account.
- `billing_history`/`subscriptions` have no client write policy. Only the backend writes them, and
  `SupabaseSubscriptionRepository.subscribeSeller` goes through `ApiEndpoints.subscribeSeller`.
- `AppConstants.useMockData` is still `true` for catalog/orders/subscriptions/admin. Flipping it needs
  a real CJ Dropshipping account, a confirmed IntaSend production setup, and
  `firebase functions:secrets:set` run with real values — none of that is done here. Identity
  (`AuthRepository`/`StoreRepository`) is no longer gated by this flag at all — see the Architecture
  section above.
- The Supabase migration has been tested only in PGlite (`supabase/tests`), not yet applied to the real
  project. Password reset has no set-new-password screen yet: Supabase redirects back to the app
  rather than hosting one. See `WORKLOG.md`, 2026-09-26, "Still open".
