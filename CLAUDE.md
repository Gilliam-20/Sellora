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

Tests live in `test/` (in-memory fakes in `test/fakes/`): `flutter test`, a single file with
`flutter test test/foo_test.dart`, a single case with `--plain-name 'description'`.
`seller_shell_controller_test.dart` has one known pre-existing failure (`NotificationCenter` not
registered).

Only `android/` and `web/` platform folders exist; there is no `ios/`. Run
`flutter create . --org com.yourcompany.sellora --project-name sellora` to scaffold what's
missing — it only adds absent platform folders and won't touch `lib/` or `pubspec.yaml`.

### Supabase (Auth, Postgres, Storage, Edge Functions)

```bash
cd supabase
npm install             # includes Deno, as an npm devDependency
npm test                # migrations + RLS checks in PGlite (no Docker), grant-admin tests,
                        # then the Edge Function tests under Deno
npm run test:functions  # just the Edge Function tests
npm run check:functions # deno type-check of functions/api/index.ts
npx supabase link --project-ref <ref>   # once
npx supabase db push                    # apply supabase/migrations to the linked project
npm run deploy                          # supabase functions deploy api
npm run serve                           # local function; secrets from functions/.env (gitignored)
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/grant-admin.js admin@example.com
```

Deno tooling must run from `supabase/functions/` with `--config deno.json` (the npm scripts do),
or Deno picks up `supabase/package.json` and can't resolve `npm:` imports.

The app reads its project URL and publishable key from `lib/core/config/supabase_config.dart`
(`--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...` overrides). Any schema
or policy change goes in a **new** migration file, with a matching check in
`supabase/tests/rls.test.mjs`.

### Firebase (what remains: hosting)

```bash
firebase deploy --only hosting
```

`functions/` is the retired Firebase Cloud Functions backend, kept only until the owner deletes the
deployed functions and its untracked `functions/.env`. Don't extend it — the backend is
`supabase/functions/`.

## Architecture

### There is no demo mode

As of 2026-09-26 (see `WORKLOG.md`) the app has no mock data: `AppConstants.useMockData` and
`lib/data/repositories/mock/` are gone, and `InitialBinding` always binds the `Supabase*`
repositories plus `CjDropshippingService`/`IntasendService`. Running the app at all requires a
reachable Supabase project (`SupabaseConfig`) with `supabase/migrations` applied. Anything that goes
through `ApiEndpoints` — the CJ catalog/import, checkout, subscription payments — also needs the
`api` Edge Function deployed with real CJ/IntaSend secrets, so those screens show errors or empty
states until then.

In-memory fakes for controller tests live in `test/fakes/` (`MockAuthRepository`,
`MockStoreRepository`, `MockOrderRepository`, `MockSubscriptionRepository`, `MockAdminRepository`,
plus `mock_seed_data.dart`). They are test code only — never import them from `lib/`.

**Firebase → Supabase is done in code** (see `WORKLOG.md`, 2026-09-26 and 2026-09-27) but not yet
applied to the real project. Phase 1 moved Auth and the database: `supabase/migrations/` holds the
schema, and its RLS policies/guard triggers replace `firestore.rules`. Sign-up creates the profile
(and a seller's store) in the `handle_new_user` trigger, not from the client. Phase 2 ported the
backend to one Edge Function, `supabase/functions/api/index.ts` (handler in `handler.ts`; routes `/functions/v1/api/<name>`),
with the logic in `supabase/functions/_shared/` (plain JS, ported from `functions/lib`). Scheduled
jobs are pg_cron → pg_net → `/cron/<job>`. PayPal and product reviews were not ported.

`orders` carries server-only columns (supplier cost, provider refs, CJ/refund state machines) behind
a column-level grant: a client `select *` on `orders` is refused, so reads name
`SupabaseOrderRepository.columns`. Firestore transactions became compare-and-set UPDATEs in the
function (CJ push and refund claims) or SQL functions (`activate_subscription`,
`attach_order_payment_attempt`, `consume_rate_limit`).

The backend and the non-identity `Supabase*Repository` classes should still be treated as
scaffolded-but-unexercised: **the app has never run its catalog/order/payment flows against a real
backend**, only identity.

Every repository is still an abstract interface with a `Supabase*` implementation in
`lib/data/repositories/`. Adding a method to an interface that has a fake in `test/fakes/` (or an
inline `_Fake*` in a test) means adding it there too, or the tests stop compiling. `CartRepository`
is in-memory by design and has a single implementation.

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

### Secrets live in the Edge Function, never in the app

The Flutter app never calls CJ Dropshipping or IntaSend directly. It calls Sellora's own `api` Edge
Function (`ApiEndpoints` in `app_constants.dart`), which holds the real keys as Supabase function
secrets (`CJ_API_KEY`, `INTASEND_SECRET_KEY`, `CRON_SECRET`, optional
`INTASEND_WEBHOOK_CHALLENGE`/`ALLOWED_REDIRECT_ORIGINS`). `DioClient` attaches the Supabase access
token (JWT) to every request. The function has gateway JWT checks off (`supabase/config.toml`) because
browsing and the webhook are public, so each signed-in route goes through `signedIn()` →
`verifyAuth`, which checks the token with Supabase Auth. That is the only thing between the open
internet and the secret keys: any new route must use it. The function uses the service role, which
bypasses RLS, so it re-checks ownership itself (`loadOwnedOrder` etc.).

It authenticates with **one platform-level credential per provider**, not per seller.

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

- The IntaSend webhook (`intasendWebhook` in `supabase/functions/api/handler.ts`) is implemented from
  their published docs, not verified against a real account — reconfirm the exact payload shape before
  going live. It checks the optional `INTASEND_WEBHOOK_CHALLENGE` secret when set.
- Admin is `app_metadata.role` only: one dedicated email, provisioned solely by
  `supabase/scripts/grant-admin.js` (no in-app admin sign-up). The `seller`/`buyer` distinction
  in RLS still reads `profiles.role`. Self-escalation is blocked by the sign-up trigger and
  `profiles_guard_update`, but it's still a table column, not a JWT claim.
- The current checkout assumes one seller per cart — `createOrder` now rejects a mixed-seller cart
  outright rather than silently misattributing it, but doesn't split it either.
- CJ Dropshipping's auth handshake and response shapes vary by account type;
  `supabase/functions/_shared/cjApi.js`/`cjAuth.js` sketch the flow but field names need confirming
  against a real CJ developer account.
- `billing_history`/`subscriptions` have no client write policy. Only the backend writes them, and
  `SupabaseSubscriptionRepository.subscribeSeller` goes through `ApiEndpoints.subscribeSeller`.
- With the mocks gone, the catalog/orders/subscriptions flows need the `api` Edge Function deployed, a
  real CJ Dropshipping account, and a confirmed IntaSend production setup with real secrets — none of
  that is done here.
- The Supabase migration has been tested only in PGlite (`supabase/tests`) and the Edge Function only
  with Deno unit tests; neither has run against the real project. Password reset lands on
  `/reset-password` and a bad link on `/auth-link-error`, both routed from `SelloraApp.onReady`.
  Auth email links return to the web page that asked, or to `sellora://auth-callback` on Android.
  See `WORKLOG.md`, 2026-09-26 and 2026-09-27.
