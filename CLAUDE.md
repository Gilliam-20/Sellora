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
npm run build     # tsc
npm run serve     # build + firebase emulators:start --only functions
npm run deploy    # firebase deploy --only functions
npm run logs
```

### Firebase

```bash
flutterfire configure                                    # generates lib/firebase_options.dart
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only hosting
```

## Architecture

### The mock/real switch is the central design fact

`AppConstants.useMockData` (`lib/core/constants/app_constants.dart`) is a single `const bool` that
decides which repository implementations `InitialBinding` binds. When `true` the entire app runs on
in-memory mocks — no Firebase project, IntaSend account, or CJ Dropshipping key required — and every
screen is clickable end to end.

This is currently `true`, and `Firebase.initializeApp()` is still commented out in `lib/main.dart`.
**The app has never run against a real backend.** Treat anything in `firestore.rules`,
`functions/src/`, or the `Firebase*Repository` classes as scaffolded-but-unexercised.

The consequence for any change: **every repository is an abstract interface with two implementations**
— a `Firebase*` one in `lib/data/repositories/` and a mock in `lib/data/repositories/mock/`. Adding a
repository method means implementing it in both, or demo mode breaks. `CartRepository` is the single
deliberate exception (in-memory either way, so one implementation).

### View → Controller → Repository, via GetX

Dependency lifetime is split across exactly two places:

- `lib/app/bindings/initial_binding.dart` registers every service and repository once, as
  `permanent: true`. Nothing else registers app-wide singletons.
- Each route's own `Bindings` class `Get.lazyPut`s its controllers, so a controller is constructed
  when its page is pushed and disposed when popped.

Models in `lib/data/models/` are plain Dart with `fromMap`/`toMap` — no Firestore types and no
Flutter imports leak into them. `FirestoreService` exists so repositories never hold raw collection
path strings.

### Secrets live in Cloud Functions, never in the app

The Flutter app never calls CJ Dropshipping or IntaSend directly. It calls Sellora's own Cloud
Functions (`ApiEndpoints` in `app_constants.dart`), which hold the real keys server-side.
`DioClient` (`lib/core/network/dio_client.dart`) attaches the Firebase ID token to every request;
`requireAuth` in `functions/src/auth.ts` verifies it and is the only thing between the open internet
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

- `intasendWebhook` in `functions/src/intasend.ts` logs the payload but does **not** verify the
  signature — there is a `TODO` where verification belongs.
- `CheckoutController` prices the cart client-side and writes an order with a client-set `total` and
  `paymentReference`. Order creation needs to move server-side before real money moves.
- `firestore.rules` trusts the client-writable `users/{uid}.role` field via a `get()` on every rule
  evaluation. This should be Firebase Auth custom claims.
- The current checkout assumes one seller per cart.
- CJ Dropshipping's auth handshake and response shapes vary by account type; `functions/src/cj.ts`
  sketches the flow but field names need confirming against a real CJ developer account.
