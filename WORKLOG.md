# Work log

Append-only record of design and implementation work, newest first. Each entry states what was
decided, what actually changed on disk, and what is still blocked — so a later session can pick up
without re-deriving the reasoning.

---

## 2026-09-27 — Firebase → Supabase, phase 2: backend on Edge Functions; auth links; Storage

**Status:** done in code. **Nothing is applied to or deployed on the real Supabase project yet** —
TODO.md's owner checklist has the steps. `cd supabase && npm test`: 89/89 SQL/RLS checks in PGlite,
7/7 grant-admin tests, and 63 Deno tests (261 steps). `deno check` and `deno lint` are clean.
`flutter analyze`: 0 errors/warnings (the same 2 pre-existing infos). `flutter test`: 51/52, and
the one failure is the same pre-existing `seller_shell_controller_test.dart` `NotificationCenter`
failure. The backend has never talked to a live CJ or IntaSend account, same as the Firebase version.

**Why:** user request: "finish up with the supabase migration in the todo.md". That covers every
open code item in the checklist: phase 2, the Android deep link, the expired-link landing, and
Storage uploads. Hosting is still the owner's decision.

**Decisions:**
- **One Edge Function, `api`, routed by path** (`/functions/v1/api/<endpoint>`). It keeps the
  Cloud Functions' endpoint names, request bodies and `{success, data}` envelope, so the app changed
  only `ApiEndpoints.baseFunctionsUrl`. Gateway JWT verification is off (`supabase/config.toml`),
  because catalog browsing and the IntaSend webhook are public. Each signed-in route checks the token
  with Supabase Auth itself (`verifyAuth`: refuses deleted and banned users). Admin comes from
  `app_metadata.role`.
- **Logic ported as plain-JS ES modules** in `supabase/functions/_shared/`, close to verbatim from
  `functions/lib`. That keeps the review diff small and the 250 existing tests reusable: they
  run under Deno's `node:test`, and only 5 needed changes for intended behaviour differences. axios
  became a small `fetch` helper (`http.js`). The Firebase logger became JSON lines on stdout, and
  the `event`/`alert` fields are unchanged.
- **Server-only order data stays on `orders`, hidden by a column-level grant.** Supplier cost,
  provider refs, and the CJ push/refund state machines are server-only columns. A client `select *`
  is refused outright, so `SupabaseOrderRepository.columns` names the readable ones. That also means
  a future server column can't leak by default. The old orders/{id}/items subcollection is the
  `lines` jsonb column. The client-visible fee columns are now in the order's own currency (the
  Firestore version wrote USD figures next to a KES/GBP/EUR total), and the USD originals are kept
  server-side.
- **Firestore transactions → compare-and-set or SQL functions.** Fulfilment's claim is
  `UPDATE ... WHERE cj_order_status = <seen> AND cj_push_attempts = <seen>`. Every claim bumps the
  attempt count, so only one of two racers can match. Refunds claim the same way on
  `(refund_status, refunded_amount)`. Multi-row writes are SQL functions callable only by the service
  role: `activate_subscription` (billing entry + subscription + profile mirror, idempotent on
  `status = 'pending'`), `attach_order_payment_attempt` (appends to the history in one statement,
  and won't reopen a paid order), and `consume_rate_limit` (row-locked fixed window, which replaces
  the Firestore counters and their TTL).
- **Payment states:** `payment_status` now allows `awaiting_confirmation`, `partially_refunded`
  and `refunded`. The Firestore version wrote `AWAITING_CONFIRMATION`, and the phase 1 check
  constraint would have rejected it. Dart's `OrderPaymentStatus` gained `partiallyRefunded` and
  `refunded`, and `awaiting_confirmation` reads as `pending`. Order `status` now goes
  `pending` → `processing` on payment (it used to be `pendingPayment`/`paid`, which the app's
  enum couldn't read).
- **Scheduled jobs:** pg_cron + pg_net POST to `/cron/<job>` with an `x-cron-secret` header read
  from Vault. The function answers 202 and finishes the job in `EdgeRuntime.waitUntil`. Jobs: FX
  daily, catalog sync daily, fulfilment retry every 30 min, tracking hourly, and rate-limit cleanup
  hourly (plain SQL). `maxDetailCallsPerRun` dropped from 60 to 20 to stay inside an Edge Function's
  wall-clock limit.
- **Not ported:** PayPal (the app never called it), product reviews (nothing reads them), and App
  Check (Firebase-only, and it was report-only). `refunds.chargedAmount` now returns null for a
  PayPal order.
- **Fixed on the way:** `placeOrder` read `res['id']` from the `{success, data}` envelope, so it
  would have thrown on the first real order. It now unwraps `data` and uses the server's short
  `code` (`SLR-XXXXXXXX`). `fulfillOrder` now refuses to re-mark a refunded order paid (a late
  webhook retry), and it no longer walks a seller-advanced status back to processing.
- **Auth links:** `AuthService.authRedirectUrl` is the current page on web and
  `sellora://auth-callback` on Android. The intent filter is in AndroidManifest.xml, and
  `flutter_deeplinking_enabled` is off so Flutter doesn't also push the URL as a route. Reset,
  sign-up and resend all pass it. A bad link (`#error=...&error_code=otp_expired`, or a PKCE link
  opened on another device) lands on `/auth-link-error`. On web, `main()` reads it from the launch
  URL and replaces the URL before the router starts, since supabase_flutter only cleans the URL on
  success. Elsewhere, `AuthService.linkErrors` carries it, including one that arrived before
  `onReady` subscribed.
- **Storage:** a public `store-media` bucket (2MB, images only). Owners write under `{store_id}/`,
  and `owns_store()` checks the first path segment. Customize store uploads the photo and saves its
  public URL. Existing `data:` logos still render.

**Changed:**
- New: `supabase/functions/` (`api/index.ts`, `_shared/*.js`, `tests/`, `deno.json`),
  `supabase/config.toml`, and migrations `20260927000000_backend.sql`,
  `20260927000100_scheduled_jobs.sql` and `20260927000200_storage.sql`. `supabase/package.json` now
  has Deno as a devDependency and test/check/serve/deploy scripts. `rls.test.mjs` has stubs for the
  storage schema and 38 new checks.
- `ApiEndpoints`, `SupabaseOrderRepository` (columns + envelope), `OrderModel`,
  `StoreRepository.uploadStoreImage` (plus the three fakes), `StoreCustomizeController`,
  `AuthService`, `main.dart`, routes, the new `AuthLinkError`/`AuthLinkErrorView` with 7 tests,
  AndroidManifest.xml, and comments across `lib/` that pointed at `functions/lib`.
- `test/countries_test.dart` now syncs against `supabase/functions/_shared/regions.js`.
- `functions/` is **left in place**, retired. It holds an untracked `functions/.env` with live keys,
  which can't be recovered once deleted, so deleting it is an owner step (TODO.md).

**Still open:**
1. Everything in TODO.md's owner list: `db push`, function secrets + deploy, Vault secrets for cron,
   the IntaSend webhook URL, redirect URLs, admin, plan seed, catalog sources, and a smoke test.
2. Unverified against real accounts (unchanged from Firebase): CJ auth/response shapes, IntaSend
   status/refund shapes, and the webhook payload. `shippingAddress` is still `{countryCode, line}`,
   not the full address CJ needs to fulfil.
3. The web link-error path relies on `SystemNavigator.routeInformationUpdated` replacing the URL before
   the router reads its initial route. That's reasoned from the engine source, not run in a browser.
4. Hosting decision (Supabase has none).

---

## 2026-09-26 — Mock data removed from the app

**Status:** done. `flutter analyze`: 0 errors/warnings (the same 2 infos, one of which now sits in
`test/fakes/mock_admin_repository.dart`). `flutter test`: 44/45. The one failure is the same
pre-existing `seller_shell_controller_test.dart` `NotificationCenter` failure.

**Why:** user request: "remove all the mockdata in the app". This came right after confirming that the
app fetches nothing real from CJ. The user was told that the real backend path doesn't work until
phase 2.

**Changed:**
- Removed `AppConstants.useMockData`. `InitialBinding` now always binds the `Supabase*` repositories
  and always registers `CjDropshippingService`/`IntasendService`.
- Removed the demo branches in `CheckoutController` (an instant fake "paid" order),
  `SellerOnboardingController.payWithMpesa`, and `SellerSubscriptionController.switchPlan` (both
  relied on the mock activating the subscription synchronously).
- Deleted `mock_product_repository.dart`, `mock_notification_repository.dart`, and
  `mock_fx_rate_repository.dart`. Moved `mock_{auth,store,order,subscription,admin}_repository.dart`
  and `mock_seed_data.dart` to `test/fakes/`, because the admin dashboard and onboarding controller
  tests use them as in-memory doubles. `lib/data/mock/` and `lib/data/repositories/mock/` no longer
  exist.
- Deleted `test/auth_repository_test.dart` and `test/mock_subscription_repository_test.dart`. They
  only tested the mocks' own behaviour. The real sign-up/store creation is covered by
  `supabase/tests/rls.test.mjs`.
- Updated comments, `CLAUDE.md`, `README.md`, and `TODO.md`. `SELLORA_IMPLEMENTATION_PLAN.md` still
  describes "mock + Firebase" implementations as history and was left alone.

**Consequence:** with the mocks gone, the running app has no fallback. Sign-in/sign-up and store
lookup work against Supabase once the migration is applied. The CJ catalog/import, checkout, and
subscription payments go through `ApiEndpoints` and fail until phase 2 ports `functions/` to Edge
Functions with real CJ/IntaSend credentials. Plans come from the `subscription_plans` table, which
is empty until seeded.

---

## 2026-09-26 — Supabase: password-reset landing screen

**Status:** implemented, not yet exercised against the real project (the migration isn't applied
there yet). `flutter analyze`: 0 errors/warnings (the same 2 pre-existing infos). `flutter test`:
50/51, and the one failure is the same pre-existing `seller_shell_controller_test.dart`
`NotificationCenter` failure. Nothing new is covered by tests, because the flow depends on
`Supabase.instance`.

**Why:** item 2 of phase 1's "Still open" list, and the first code item in TODO.md's Supabase
checklist. Without it, reset emails and `grant-admin.js`'s first-login link led nowhere.

**Findings from the gotrue 2.25 / supabase_flutter 2.15 source:**
- A recovery link emits **only** `passwordRecovery`, never `signedIn`. That holds for both the PKCE
  `?code=` link from `resetPasswordForEmail` and the implicit `#access_token=…&type=recovery` link
  that `admin/generate_link` produces. `SupabaseAuthRepository.userChanges` skips that event.
  Before this change, a recovery link left the app signed in, with no screen and no cached profile.
- `Supabase.initialize()` consumes the launch URL before `runApp`, so the event fires before any
  widget exists. `onAuthStateChange` is a BehaviorSubject, though, so a late listener still receives
  it as the latest event.

**Changed:**
- `AuthService`: tracks `isRecoveringPassword`. It is set by `passwordRecovery` and cleared by
  `signedIn`/`signedOut`/`userUpdated`. It also exposes `passwordRecoveries` and
  `updatePassword()`. `sendPasswordReset` passes `redirectTo` on web, which is the current
  origin + path, so a dev server gets the link back. That URL must be in the redirect allow-list.
- `AuthRepository`: adds `passwordRecoveries`, `isRecoveringPassword`, and `updatePassword()`,
  which returns the profile loaded with a token refresh and caches it. There are implementations in
  the Supabase repo, the mock, and both test fakes. `same_password` maps to `same-password`.
- `SelloraApp.onReady` (in `main.dart`) listens for `passwordRecoveries` and routes to the new
  `/reset-password` route (`ResetPasswordView`: new password + confirm, using
  `Validators.newPassword`). On success, `AuthController.completePasswordReset` routes the user
  home the way sign-in does, and the suspended-seller check applies there too. If the screen is
  opened without a recovery session, it shows "This link has expired" instead.
- `AuthController.checkSession` returns early during recovery. Otherwise the mobile splash's 3-second
  fallback would call `offAllNamed(roleSelect)` over the reset screen.

**Still open:**
- **Android has no deep-link intent filter**, so a reset requested on the app goes to the web Site
  URL. The PKCE code verifier lives on the device that asked for the reset, so the code exchange
  there will fail. Either add an app link (and pass it as `redirectTo` off-web) or set
  `flowType: AuthFlowType.implicit`. Web-to-web works.
- An expired or used link arrives as a stream error (`#error=access_denied&error_code=otp_expired`).
  Nothing routes on it, and with hash routing GetX reads that fragment as a route.

---

## 2026-09-26 — Firebase → Supabase, phase 1: Auth + database

**Status:** implemented this session, **not yet applied to the Supabase project**. `flutter analyze`:
0 errors/warnings (the 2 pre-existing infos). `flutter test`: 50/51. The one failure is the same
pre-existing `seller_shell_controller_test.dart` `NotificationCenter` failure. There are 5 new
row-mapping tests. `cd supabase && npm test`: 51/51 schema/RLS checks plus 7/7 grant-admin tests.
`functions/` `npm test`: 250/250.

**Why:** user request: "switch firebase to supabase". Agreed scope: phase 1 is Auth + database. Phase
2 ports `functions/` to Supabase Edge Functions (Deno), with `pg_cron` replacing the four scheduled
functions. Hosting stays undecided. Supabase has no static hosting, so `firebase.json` keeps its
`hosting` block until then.

**Decisions:**
- **Models are untouched.** Columns are snake_case. `toRow`/`fromRow` in
  `lib/data/services/supabase_service.dart` translate top-level keys, and jsonb columns keep
  camelCase inside. They also translate timestamps. `DateTime.toIso8601String()` on a local
  DateTime has no offset, so Postgres would read it as UTC and shift it by the device's offset (3h
  in Kenya). Offset-less strings are sent as UTC, and `+00:00` values come back as local ISO strings.
- **The profile is created by a trigger, not the client.** `signUp()` passes the profile fields as
  user metadata. `handle_new_user()` then creates the profile, plus a seller's store (same slugify
  and `-N` rule as Dart) or a buyer's `store_customers` row, in the same transaction as
  `auth.users`. It accepts only what a buyer or seller sign-up can legitimately produce. This
  retires the old create-rule field policing and `_deleteAuthUserOnFailure`, and it works whether
  or not "Confirm email" is on.
- **Admin:** `app_metadata.role = 'admin'` replaces the `admin` custom claim. Only the service role
  can set it. `is_admin()` checks it, and the `profiles.role` column stays routing-only. The
  `grant-admin.js` port lives in `supabase/scripts/`. It has no npm dependencies (it calls the REST
  APIs with fetch) and needs `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.
- **One `orders` table** replaces the flat `orders` collection plus `stores/*/orders`. RLS gives
  the cross-tenant guarantee the subcollections were for. `store_slugs` became a unique constraint.
- **Clients may write only a few order/notification columns.** A column-level `grant update` allows
  `orders(status, updated_at)` and `notifications(read_at)` only. Guard triggers make profile
  role/subscription/approval/terms/store and store id/slug/owner immutable to clients.
  `profiles_guard_update`/`stores_guard_update` replace `touchesAny()`.

**Changed:**
- `pubspec.yaml`: `firebase_core`/`firebase_auth`/`cloud_firestore` → `supabase_flutter`.
  `lib/firebase_options.dart`, `android/app/google-services.json`, and the Android
  `com.google.gms.google-services` plugin are gone.
- New: `supabase/migrations/20260926000000_initial_schema.sql`, `lib/core/config/supabase_config.dart`
  (URL and publishable key; `--dart-define` overrides), and `SupabaseService`, which replaces
  `FirestoreService`. `AuthService` now wraps Supabase Auth.
- `Firebase*Repository` → `Supabase*Repository` (all seven). `SupabaseAuthRepository` maps Supabase
  error codes onto the existing `AuthFailure` codes, so `AuthController` only gained
  `email-not-confirmed`. `userChanges` ignores token-refresh/user-updated events. `updateUser` sends
  only self-editable columns. Before, `UserModel.copyWith` dropped `storeId`, so it would have
  nulled a buyer's store.
- `DioClient` sends the Supabase access token.
- Removed `firestore.rules`, `firestore.indexes.json`, and the `firestore`/`flutter` blocks in
  `firebase.json`. Their rules are carried over in the migration, and each policy's comment names
  the rule it replaces.
- New `supabase/tests/rls.test.mjs` runs the migration in PGlite (Postgres in WASM) and checks the
  trigger and every policy as anon/buyer/seller/admin. It found one real constraint: a notification
  insert must not `.select()` the new rows. The sender can't read the counterparty's alert, so
  RETURNING fails RLS. The repository has a comment on this.

**Still open / blocked:**
1. **Apply the migration** to the Supabase project (SQL editor, or `npx supabase link` + `db push`).
   Fill in `SupabaseConfig`, then re-run `grant-admin.js` for the admin. The Firebase `sellora-20`
   accounts are not migrated. Everything was pre-launch, so this assumes no real users exist.
2. **Password reset has no landing screen.** Firebase served its own reset page. Supabase redirects
   back to the app's Site URL with a recovery session, and the app has to show a set-new-password
   form (on `AuthChangeEvent.passwordRecovery`) and call `updateUser(password:)`. Until that's built,
   reset emails, and the admin's first-login link, lead nowhere useful. Set Site URL/redirect URLs in
   the Supabase dashboard at the same time.
3. **"Confirm email":** Firebase allowed immediate sign-in, and that matches Supabase with
   confirmation **off**. If it's on, sign-up shows "check your inbox" instead of entering
   onboarding. That works, but it's a UX change.
4. **Phase 2:** the deployed Cloud Functions still verify Firebase ID tokens and read/write
   Firestore. They reject Supabase tokens, which is harmless only while `useMockData` is true. The
   server-only tables (CJ catalog → `catalog_products`, `rate_limits`, refund/fulfilment columns on
   `orders`) arrive with that port.

---

## 2026-09-25 — PHASE 2: onboarding store-setup step, no-store recovery, email verification

**Status:** implemented this session. `flutter analyze`: 0 errors/warnings (3 pre-existing
`curly_braces` infos in untouched files). `flutter test`: 45/46, with the same pre-existing
`seller_shell_controller_test.dart` `NotificationCenter` failure. 8 new tests in
`test/seller_onboarding_controller_test.dart`. Not run against the live `sellora-20` project.

**Why:** user request: "work on phase 2". The only item the STATUS row listed (the multi-store
switcher) is still blocked on decision #4. This session did the unblocked Phase 2 work from TODO.md
§32–33 instead.

**Changed:**
- `StoreModel` gained `category` (a `StoreCategories.all` key) and `countryCode` (ISO alpha-2, where
  the business is based, not where it ships), plus `isSetUp` (both are set). Old store docs read
  them as null. No rules change was needed: the `stores` update rule already allows any field except
  `id`/`slug`/`sellerId`/`createdAt`.
- `createStoreForSeller()` in `store_repository.dart` is now the one place that creates a store
  (first free slug, id `store-{sellerId}`). Both auth repositories' sign-up and onboarding call it,
  which removes the copy that was duplicated in the Firebase and mock repositories.
- Seller onboarding is now 3 steps: **store setup** (name, category, country, currency; the
  currency defaults from the country) → plan → pay. A seller whose store is already set up skips to
  plan selection. Saving updates the store and mirrors `storeName`/`currencyCode` onto the user doc.
  The slug never changes. If the seller has no store, saving creates one. The screen has a back
  button between steps and an error state if plans fail to load.
- Seller shell: `StoreScope.isMissing` separates "found no store" from "the lookup failed". The
  no-store case now offers "Create my store", which opens onboarding's setup step, instead of a
  retry that could never succeed.
- `AuthRepository.checkEmailVerified()` / `resendVerificationEmail()` (the mock always reports
  verified). The store-setup step shows a verify-your-email banner with Resend and "I've verified".
  Verification is still **not required** to continue.

**Still open (Phase 2):** multi-store switcher and store-limit enforcement (decision #4); required
email verification; Google sign-in (TODO §32, "where configured"); onboarding steps 8–11 (first
import, payment, shipping, publish) are covered by the dashboard's setup checklist, not by this flow.
Existing stores created before this session have no category/country. Their sellers only see the
setup step if they come back through onboarding, for example after a subscription lapses.

---

## 2026-09-25 — Auth flow hardening; admin is one dedicated, server-provisioned email

**Status:** implemented this session. `flutter analyze`: 0 errors (2 pre-existing infos in untouched
files). `flutter test`: 36/37, the same pre-existing `seller_shell_controller_test.dart`
`NotificationCenter` failure. Functions `npm test`: 256/256 (6 new in `grantAdmin.test.js`). Rules
emulator suite: 35/35 (2 new). Not exercised against the live `sellora-20` project.

**Why:** user request — production-ready auth with security intact, and "admin has his separate email".

**Changed:**
- `firestore.rules`: `isAdmin()` is now the `admin` custom claim **only**; the `role() == 'admin'`
  fallback is gone, so no Firestore field grants admin. The `users` update rule also stops an admin
  from setting `role: 'admin'` on another account from the client.
- `functions/scripts/grant-admin.js` (new): the only way to make an admin. `node scripts/grant-admin.js
  <email> [--name ..]` creates the Auth account if needed (no password; prints a one-time reset link),
  sets the claim, and writes the `role: admin` profile. It refuses an email that is already a
  buyer/seller (the admin must use a separate email) and refuses a second admin. `--revoke` drops the
  claim, revokes refresh tokens, and deletes the profile.
- `FirebaseAuthRepository`: a `role: admin` profile without the claim is rejected
  (`admin-claim-missing`) at sign-in, session resume, and refresh. Sign-in force-refreshes the token so
  claim changes apply immediately. Firebase exceptions become a provider-neutral `AuthFailure(code)`.
  Emails are trimmed and lowercased. Sign-up sends a verification email (best effort, not enforced).
  `signOut` clears the cache.
- `AuthController`: maps errors by code, including `invalid-credential` (what Firebase returns with
  email-enumeration protection on, which previously fell through to "Something went wrong"),
  `too-many-requests`, `user-disabled`, and offline. Suspended sellers are signed out at sign-in and
  session resume. `signOut` clears `lastRole`.
- `Validators`: `password` (sign-in) only checks non-empty. The new `newPassword` (seller/buyer sign-up)
  requires 8–128 characters with letters and digits. The email regex now accepts `+` and long TLDs.
- `firestore-tests/*`: admin contexts now carry `{ admin: true }`.

**Deploy order (required, otherwise admin access is lost):** run `grant-admin.js` for the admin email
*before* `firebase deploy --only firestore:rules`. Any existing `role: admin` doc without the claim stops
working the moment the new rules deploy.

**Still open:** email verification is sent but not required for any action. Suspension is enforced in
the client only. Rules don't block a suspended seller's writes yet.

---

## 2026-09-25 — Identity is no longer mocked: Auth + Store always bind to Firebase

**Status:** implemented this session. `flutter analyze`: 0 issues (was 1 pre-existing error in
`test/auth_repository_test.dart`, unrelated to this change — fixed in passing, see below).
`flutter test`: 36/37 pass; the 1 failure (`seller_shell_controller_test.dart` missing a
`NotificationCenter` binding) pre-dates this session (confirmed via `git stash`) and is untouched.

**Why:** user request — stop the running app from sourcing sign-in/sign-up from
`MockAuthRepository`'s in-memory fake session and wire in the real `FirebaseAuthRepository`, which
already existed fully implemented but was never bound. `AppConstants.useMockData` previously switched
*every* repository together, and flipping it wholesale is blocked on a real CJ Dropshipping account and
a confirmed IntaSend production setup (see "Known gaps" in `CLAUDE.md`) — neither of which identity
depends on. `StoreRepository` moved with it rather than staying mocked, because
`FirebaseAuthRepository.signUpSeller` creates a seller's store through whatever `StoreRepository` is
bound: pairing a real, persisted Firebase Auth account with an in-memory `MockStoreRepository` would
have made a seller's own store vanish on every app restart (`MockStoreRepository` resets to
`MockSeedData`'s two seed stores on each launch) — worse than either being fully mocked or fully real.

**Changed:**
- `lib/app/bindings/initial_binding.dart`: `AuthService`, `FirestoreService`, and
  `StoreRepository`/`AuthRepository` (bound to `FirebaseStoreRepository`/`FirebaseAuthRepository`) are
  now registered unconditionally, before the `useMockData` branch, which now only covers
  Product/Order/Notification/Subscription/Admin/FxRate. `MockAuthRepository`/`MockStoreRepository` are
  no longer instantiated anywhere in the running app.
- `lib/main.dart`: `Firebase.initializeApp()` now runs unconditionally instead of being gated on
  `!useMockData`.
- `lib/core/constants/app_constants.dart`: `useMockData`'s doc comment corrected — it no longer
  describes "the entire app."
- `CLAUDE.md`, `README.md`: architecture/quickstart sections updated to describe the split (identity
  always real; catalog/orders/etc. still gated by `useMockData`) and to drop the now-dead
  "sign in with an email containing 'seller'/'admin'" quick-login shortcut, which only ever lived in
  `MockAuthRepository` and no longer applies once it isn't bound.
- `test/auth_repository_test.dart`: fixed a pre-existing, unrelated compile error (missing
  `user_model.dart` import for `sellerTermsVersion`) found while verifying this change — not part of
  the scope, but a one-line fix needed to run the suite at all.

**Deliberately not changed:** `MockAuthRepository`/`MockStoreRepository` themselves are untouched and
still exist — `test/auth_repository_test.dart` and `test/admin_dashboard_controller_test.dart` exercise
them directly (signup slug-dedup, terms-version, terms-acceptance business logic) independent of
`InitialBinding`, and rewriting that coverage against a Firebase-backed fake was out of scope.

**New consequence, disclosed:** the two demo storefronts `MockSeedData.stores()` seeds
(`aminas-picks` / `jengo-electronics`, matched to `MockProductRepository`'s seeded listings by
`storeId`) are no longer reachable by browsing — `StoreScope`/`FirebaseAuthController` now resolve
stores through real (likely empty) Firestore, which has no docs at those slugs. Only a real seller who
actually signs up gets a real, resolvable store; buyers can no longer browse a demo storefront without
one existing for real. `AppConstants.useMockData = true` still keeps that seller's *product catalog*
on mock data once inside their store, but the store itself, and getting a buyer to it, is now real.

**Still open / unverified:**
- Whether Email/Password sign-in is actually enabled on the live `sellora-20` Firebase project, and
  whether its deployed `firestore.rules` matches what's checked in here — this session read the rules
  file and reasoned the `users`/`stores`/`store_slugs` create rules support `signUpSeller`'s write
  order (user doc, then store), but did not exercise it against the real project.
- No new Firestore data was seeded for the two former demo stores; if browsable-without-signup demo
  storefronts still matter, that needs either seeding `stores`/`store_slugs` docs for them in the real
  project, or keeping a mock fallback for anonymous storefront browsing specifically.

---

## 2026-09-25 — PHASE 8: seller/store attribution + service-fee split (scaffold, no live payout)

**Status:** implemented this session. Functions (`functions`, `npm test`): 254/254 pass (4 new in
`orders.test.js`). Firestore emulator rules suite (`firestore-tests`, `npm test`): 33/33 pass, unchanged
— no `firestore.rules` edits were needed, since the fields this touches were already locked to
Cloud-Function-only writes by today's earlier PHASE 12 pass. `useMockData` is still `true`; none of this
has run against a real order.

**Why:** continuing SELLORA_IMPLEMENTATION_PLAN.md, scoped to PHASE 4 (CJ catalog/import UI) and a
PHASE 8 scaffold (seller/store/fee fields, explicitly *not* real IntaSend sub-account wiring — see the
next entry below for why PHASE 4 turned out to need no work at all).

**A deeper finding than "add sellerId/storeId fields":** `createOrder` never read a seller's own listing.
It re-derived its own retail price straight from CJ's supplier cost via `pricing.js`'s single global
margin config — the same pricing a bare single-vendor dropshipping app would use — completely ignoring
`stores/{storeId}/products/{pid}.sellPrice`, the price a seller actually set on the product_import
screen. This was already flagged, just not yet fixed: `ProductModel.sellPrice`'s own doc comment says
"what the *seller* has chosen to charge," and `FirebaseOrderRepository.placeOrder` already had an inline
comment disclosing that the adopted backend "ignores" `storeId` entirely.

**Changed:**
- `functions/lib/orders.js`'s `createOrder` now requires `storeId`, looks up
  `stores/{storeId}/products/{pid}` per line item (must exist, `isListed: true`, and the chosen `vid`
  must not be a seller-disabled variant — see `ManageVariantsController`), and prices each line at the
  seller's own `sellPrice` instead of recomputing a fresh CJ-margin price. Adds
  `buyerId`/`sellerId`/`storeId`/`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue` to the order doc.
  The `buyerId` addition closes the exact gap today's earlier PHASE 12 entry's "Still open" list flagged
  (`FirebaseOrderRepository.buyerOrders` queries `buyerId`, which no server-created order carried until
  now). `estimatedProfitUsd` (Sellora's own take) is corrected to also subtract `sellerRevenueUsd` — it
  was silently counting the seller's share as platform profit. New pure `splitServiceFee(retailSubtotalUsd)`
  (2% of product subtotal only, never shipping — the decision already on record in
  SELLORA_IMPLEMENTATION_PLAN.md) is exported and unit-tested the same way `marginPricingService.js` is.
  The order is now also mirrored, write-once, into `stores/{storeId}/orders/{orderId}` (previously
  always empty); no screen reads that path yet (`sellerOrders`, the one the seller order queue/dashboard
  actually call, already worked off the flat collection and stays the live source), so its staleness
  after creation is a known, flagged-inline limitation, not a live bug.
- `functions/index.js`'s `createOrder` handler forwards the new `storeId` field.
- `lib/data/repositories/firebase_order_repository.dart`'s `placeOrder` now reads
  `serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue` back off the response — `OrderModel` already had
  these fields (added 2026-09-11 for the earlier, since-deleted backend) but they'd sat unused since the
  2026-09-12 backend swap. Its stale comments (claiming the adopted backend has "no seller/fee/store
  concept at all") are corrected.
- `functions/test/orders.test.js`: 4 new cases for `splitServiceFee` (rate, rounding reconstitution to
  the cent, zero, negative/NaN) and `validateOrderRequest`'s new `storeId` requirement.

**Not done, deliberately (user's explicit "scaffold, not full implementation" choice):** no real
IntaSend Split Payments sub-account wiring — money still flows exactly as before, one IntaSend/PayPal
charge, no split, no payout. The five API specifics from the 2026-09-09 design entry below (split
precision, sub-account KYC turnaround, Payouts API minimums/fees, settlement schedule, refund-on-split
behavior) are still unconfirmed against a real IntaSend account and are what actually blocks turning
this snapshot into a real payout. `refundOrder`/`attachPaymentAttempt`/the payment webhooks/
`retryFailedFulfillments`/`refreshOrderTracking` do not update the new `stores/{storeId}/orders` mirror
— flagged inline in `orders.js` for whoever wires a screen to read it.

**Verification gap, disclosed:** did not drive `createOrder` itself through the Firestore/functions
emulator — that needs a mocked-CJ-API test harness that doesn't exist for this file's async paths today
(the existing `orders.test.js` only unit-tests its pure helpers; this pass follows that same pattern
rather than inventing new infrastructure). Ran the existing `firestore-tests` rules suite as a
regression check instead (33/33 pass, unchanged) — it confirms `firestore.rules` still holds, not that
this new logic is correct end-to-end.

---

## 2026-09-25 — SELLORA_IMPLEMENTATION_PLAN.md correction: PHASE 4 was already done

**Status:** documentation-only, no code changed.

**Why:** auditing "what hasn't been done" against the plan doc's own text, before starting the PHASE 8
work above, found its PHASE 4 section stale — it still read as if catalog-browse/shipping-estimate UI
didn't exist, three commits after they'd actually shipped (`git log` on the relevant files: "catalog and
cj import" 2026-09-18, "added freight options" 2026-09-22).

**What's actually true, confirmed by reading the code, not just commit messages:**
- Category browsing: `SellerCatalogController.loadCategories()` → `ProductRepository.categories()` →
  `CjDropshippingService.getCategories()` → the `getCategories` Cloud Function, rendering the seller
  catalog screen's filter chip row.
- Shipping estimate: `ProductImportController._loadShippingEstimate()` and `CheckoutController`'s
  shipping picker both call `CjDropshippingService.calculateFreight()`/`getShippingOptions()` → the
  `calculateFreight` Cloud Function.
- CJ-catalog-to-per-seller-listing import mapping: the `product_import` screen (2026-09-18/19) already
  does this — variant picker, landed-cost pricing card, save-as-draft vs. publish via `isListed`.
- Buyer-facing variant selector: also already shipped (`_BuyerVariantPicker` in
  `product_details_view.dart`) — the plan's PHASE 5 section separately claimed this didn't exist either;
  same staleness, same fix.

**What's genuinely still missing:** a server endpoint exposing the *full*
`marginPricingService.calculatePricing()` formula (advertising/refund/VAT/fx-aware) to the client —
`ProductImportController.priceForMargin` does its own simpler `landedCost * (1 + margin/100)` markup
instead. Whether that's a real gap or an intentional simplification is a product call, not a confirmed
defect, so left alone.

**Changed:** `SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 4 and PHASE 5 (variant-selector line) sections
corrected in place, marked with a `2026-09-25 correction` note rather than silently rewritten, so a
later session can see what the text used to claim. This entry.

---

## 2026-09-25 — PHASE 12: security + production audit and fixes

**Status:** implemented this session. Emulator rules suite (`firestore-tests`, `npm test`): 33/33
pass (15 new in `production-hardening.test.js`; one `tenant-isolation` setup changed, see below).
Functions (`functions`, `npm test`): 244/244 pass (17 new). `flutter analyze`: the same 3
pre-existing issues. `flutter test --concurrency=1`: only the same 2 pre-existing failures
(`auth_repository_test.dart` compile error, `seller_shell_controller_test.dart` `NotificationCenter`
setup) plus the new `slug_test.dart` passing. With default concurrency,
`admin_dashboard_controller_test.dart` also fails *to load* intermittently; it passes alone and
serially, so that's a parallel-load flake, not a regression. `flutter build web` succeeds. Nothing
deployed; `useMockData` is still `true`, so none of this has run against real Firebase.

**Why:** TODO.md's STATUS row called PHASE 12 "done" on the strength of the 2026-09-11 pull-forward.
Auditing all ten TODO areas showed real holes left, including two privilege escalations.

**Findings and what changed:**

| # | Area | Finding | Fix |
|---|---|---|---|
| 1 | Rules / auth | **Critical.** `users` *create* didn't restrict `role`: a brand-new account could create its own doc with `role: 'admin'` (or an active subscription). The 2026-09-11 fix only locked *update*. | Self-create now only allows `buyer`/`seller`, `sellerStatus` null/`pendingApproval`, no subscription fields. This matches exactly what `signUpBuyer`/`signUpSeller` write. |
| 2 | Rules / payments | `stores/{id}/orders` *create* was client-allowed with any `total`. | `create: if false`, like flat `orders`. No client wrote there. |
| 3 | Rules / payments | A seller (or admin) could update **any** order field, e.g. `paymentStatus: 'paid'` + `cjOrderStatus: 'FAILED'`, which would get `retryFailedFulfillments` to push an unpaid order to CJ on Sellora's wallet. | Sellers: only `status` (must be an `OrderStatus` value) + `updatedAt`. Admins: anything except `serverOwnedOrderFields()`. |
| 4 | Rules / tenancy | Store `slug` was mutable and not unique. A seller could re-point their store at another seller's `/s/:slug`. Any signed-in user (not just sellers) could create stores. | New `store_slugs/{slug}` reservation written in the same batch as the store (`FirebaseStoreRepository.createStore`); `stores` create requires it, the `seller` role, and a well-formed slug. `id`/`slug`/`sellerId`/`createdAt` are immutable. `slugify` caps at 60 chars. |
| 5 | Rules / permissions | Functions authorize admins by the `admin` custom claim, while rules used only the `role` field. Two sources of truth. | New `isAdmin()` accepts the claim (checked first, no doc read) or `role`. |
| 6 | Rules / data | `createOrder` stores the buyer as `userId`/`uid`, but rules only let `buyerId` read. Buyers couldn't read their own server-created orders. | Flat `orders` read accepts `userId` too. (The client still *queries* `buyerId`, see Still open.) |
| 7 | Rate limiting | No per-user limits, only global `maxInstances`. `payOrderMpesa` could be looped to spam STK prompts at a phone. | New `functions/lib/rateLimit.js`: Firestore fixed-window counters (`rate_limits/{policy}_{uid}`, Admin-only) on every signed-in endpoint, 429 + `Retry-After`. It fails open if Firestore itself errors. |
| 8 | Error handling | `sendError` returned raw `err.message` with a 500: CJ/IntaSend error bodies, Firestore paths. The public webhooks echoed it too. | New `functions/lib/errors.js` (`HttpError`, `badRequest`/`notFound`/`unprocessable`). Only those messages reach callers; everything else becomes a generic 500 and is logged in full. Validation throws in `orders.js`/`reviews.js`/`subscriptions.js` converted, so they now return 400/404/422 instead of 500. |
| 9 | Validation | `calculateFreight` forwarded `products[]` to CJ unbounded and unvalidated. `phoneNumber` was unchecked. Ids went straight into doc paths. | `validateFreightRequest` (≤50 lines, `sanitizeId` vids, int quantity 1–20, 2-letter countries), `isValidMpesaPhone` (`^254[17]\d{8}$`, same as the client validator), `sanitizeId` on every `orderId`/`billingEntryId`. |
| 10 | Payment security | `redirectUrl`/`returnUrl`/`cancelUrl` were passed to IntaSend/PayPal as sent: an open redirect off a trusted payment page. | `isAllowedRedirectUrl`: https + an allowlisted origin (Hosting domains + sellora.app, override with `ALLOWED_REDIRECT_ORIGINS`). `http://localhost` is accepted only under the emulator. |
| 11 | Authentication | `verifyIdToken` didn't check revocation, so a disabled account's token worked for up to an hour. | `verifyIdToken(token, true)`. Costs one Auth lookup per signed-in request. |
| 12 | Secrets | No secret is committed; `git log -S` finds none of the credential values in history. `functions/.env` is gitignored. | No change. See Still open about that file. |

A test fixture changed: `tenant-isolation.test.js`'s "store owner cannot read another store's
orders" used a *buyer creating a store order with `total: 1000`* as setup, which is finding #2. It
now seeds the order with rules disabled; its read assertions are unchanged.

**Audited, no change needed:** `requireAuth` precedes every non-public handler. The webhooks re-verify
with the provider and bind invoice → order, so a forged IntaSend webhook can't fulfil anything.
`cors: true` is fine because auth is a bearer token, not a cookie. Public browse endpoints are already
clamped (`params.js`) and cached. The client surfaces the server's `message`, so the new 429 and
generic-500 texts reach users with no client change.

**Still open (not attempted this session):**
- Admin access still falls back to the Firestore `role` field. Set the `admin` claim on every admin
  (`setCustomUserClaims`), then delete the `role() == 'admin'` half of `isAdmin()`.
- App Check is report-only (`ENFORCE_APP_CHECK`); the Flutter client doesn't send tokens yet.
- Configure a Firestore TTL policy on `rate_limits.expireAt` at deploy time; without it, counter docs
  accumulate (one per user per policy, so bounded but never cleaned).
- `functions/node_modules` (5,168 files) is tracked in git from before `.gitignore` covered it.
  `git rm -r --cached functions/node_modules` fixes it; not done here because it's a large commit
  the owner should make deliberately.
- `functions/.env` holds live-looking provider credentials in plaintext. These belong in Secret Manager
  (`firebase functions:secrets:set`). A `.env` key with the same name as a `defineSecret` param also
  conflicts at deploy.
- `FirebaseOrderRepository.buyerOrders` queries `buyerId`, which server-created orders don't have.
  Rules now permit reading by `userId`, but the query and `OrderModel.fromMap` still need
  reconciling with `createOrder`'s shape (a data-model gap, not a security one).
- Crashlytics/monitoring, Firestore backups, deployment runbooks, performance profiling.

---

## 2026-09-25 — PHASE 11: internationalization (first slice)

**Status:** implemented this session. `flutter analyze` shows only the same 3 pre-existing issues
(`responsive.dart`/`mock_admin_repository.dart` curly-brace info, `test/auth_repository_test.dart`'s
missing-`sellerTermsVersion` compile error). `flutter test`: the new `money_test.dart` and
`countries_test.dart` pass (19 cases) along with `admin_dashboard_controller_test.dart`; the only
failures are the same two pre-existing ones (that compile error, and `seller_shell_controller_test.dart`'s
`NotificationCenter` setup gap). `flutter build web` succeeds. Not click-through-verified in a live
browser this session.

**Why:** TODO.md's PHASE 11 lists multi-currency, country configuration, shipping zones,
international payment architecture and localization readiness. Auditing first showed the server
already had most of the currency backbone — `functions/lib/regions.js` (country → pricing region →
currency) and `functions/lib/fx.js` (a daily USD-base rate cache at `config/fx`) — while the Flutter
side had a USD/KES-only display toggle on a hardcoded `AppConstants.usdToKesRate`, a hand-picked
5-country checkout list, and M-Pesa as the *only* payment option for every country, including US/UK/EU
buyers who can't use it. This slice closes the client-side gaps against what the server already does.

**Changed:**
- **New `lib/core/i18n/`:**
  - `currencies.dart` — `CurrencyInfo`/`Currencies` registry (KES, USD, GBP, EUR: symbol, name,
    minor-unit digits). `Formatters.currency` now reads symbols/decimals from it.
  - `money.dart` — `Money`, an integer-minor-unit amount (build spec §36). Exact `+`/`-`/`× quantity`,
    one explicit rounding for `scale`/`convertTo`, and throws on mixing currencies. Models still store
    `double` major units — `Money` is used at the arithmetic sites (cart subtotal, checkout total,
    conversion), not persisted.
  - `countries.dart` — `CountryConfig`/`Countries` (KE, US, GB + all 27 EU members), `ShippingZone`
    (kenya/us/uk/eu — the same ids and currencies as regions.js's regions, including its US/USD
    fallback for unknown countries), and `PaymentMethodType` (M-Pesa for Kenya only; card everywhere).
    `test/countries_test.dart` parses regions.js and fails if the two drift apart.
  - `app_locales.dart` — `flutter_localizations` delegates + `supportedLocales`, wired into
    `GetMaterialApp`. English only, deliberately — see "Still open".
- **FX rates:** new `FxRates` model (pivot logic mirrors fx.js's `pivotRate`; `FxRates.fallback`
  mirrors its `FALLBACK_RATES`), `FxRateRepository` with `FirebaseFxRateRepository` (reads `config/fx`)
  and `MockFxRateRepository`, both bound in `InitialBinding`. `firestore.rules` opens **only**
  `config/fx` for public read (it's market data the server writes; the rest of `config` stays denied).
- **`CurrencyService`** supports all four currencies, converts via `Money` using the loaded rate table
  (`refreshRates()` fires once at startup, falls back silently), and exposes `isConverted()`.
  `AppConstants.usdToKesRate` is deleted. The buyer profile's USD/KSh segmented toggle is now a
  four-currency dropdown.
- **Shipping zones:** `StoreModel.shippingZones` (zone ids; a document without the field defaults to
  all zones — the same countries checkout offered before). "Customize store" gains a Shipping zones
  section (can't disable the last zone). Checkout's country dropdown now lists only countries in the
  store's zones, Kenya first.
- **Checkout:** CJ freight quotes (`FreightOption.currency`, USD) are converted into the cart's
  currency before being added to the subtotal — previously the raw numbers were summed regardless of
  currency (latent today since listings default to USD too, but wrong the moment a store prices in
  KES). Totals are computed in `Money`. A payment-method picker offers what the destination country
  supports; the M-Pesa phone field only shows for M-Pesa. Real-mode card payment calls the existing
  `payOrderCard` endpoint and opens IntaSend's hosted page via the new `url_launcher` dependency;
  `CheckoutController.placeOrder` also refuses a method the country doesn't support, not just the UI.
  A note appears when prices are shown converted.
- **pubspec:** added `url_launcher`, `flutter_localizations`; `intl` bumped `^0.19.0` → `^0.20.2`
  (flutter_localizations pins 0.20.2; only `NumberFormat`/`DateFormat` are used, unchanged).

**Still open (not attempted this session):**
- Shipping zones are enforced client-side only. The adopted single-vendor `createOrder` has no
  store concept to check a store's zones against — same root gap as PHASE 8's service-fee note.
- Every IntaSend charge is still in KES (`payOrderCard`/`payOrderMpesa` charge `order.totalKes`),
  so a GBP/EUR buyer's card is charged the KES equivalent. A true multi-currency settlement needs
  either IntaSend multi-currency confirmation or a second provider (`paypalApi.js` exists server-side,
  unreconciled). There's still no `PaymentProvider` interface — checkout switches on
  `PaymentMethodType`, which is a step toward one, not the abstraction itself.
- Monetary *models* (`OrderModel.total`, `ProductModel.sellPrice`, …) are still `double`; moving
  persisted amounts to minor units needs a coordinated server/Firestore migration.
- No per-store currency selector: `StoreModel.currencyCode` exists, but products carry their own
  `currency` and nothing re-prices them when a store's currency changes, so exposing it would mislead.
- Localization is wired but English-only: all UI strings are still inline literals. Next step is
  extracting them into ARB files (`flutter gen-l10n`) before adding e.g. Swahili.
- `CurrencyService` has no unit test of its own (`StorageService`/`GetStorage` need test setup
  nobody has built yet); its conversion logic is covered through `FxRates`/`Money` tests.

---

## 2026-09-25 — Sellora visual identity assets

**Status:** implemented this session. Focused `flutter analyze` of the updated splash view completed
without reported issues. No behavioral, routing, backend, or theme-token changes were made.

**Changed:**
- Added `assets/images/sellora-splash-logo.png`, the supplied Sellora wordmark/tagline artwork, and
  changed the in-app `SplashView` to a white background using that asset instead of the previous
  navy, text-rendered wordmark/tagline.
- Added `assets/images/sellora-app-logo.png`, the supplied cart/S app mark. It appears above the
  wordmark in `SplashView` and was rendered into each Android launcher-icon density at
  `android/app/src/main/res/mipmap-*/ic_launcher.png` (mdpi through xxxhdpi). The Android manifest
  already points at `@mipmap/ic_launcher`, so no manifest change was needed.
- Replaced `web/favicon.png` with the supplied favicon artwork, rendered as a 32×32 PNG. The existing
  `web/index.html` favicon reference remains unchanged and now serves the new icon.

**Still open:** iOS is not present in this repository, so no iOS app-icon asset was added. The web
PWA manifest icons were intentionally left unchanged; the request was specifically for the browser
favicon.

---

## 2026-09-22 — PHASE 10: admin platform-financial overview + Stores tab (first slice)

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as every
recent entry — `responsive.dart`/`mock_admin_repository.dart` curly-brace lint info, and
`test/auth_repository_test.dart`'s missing-`sellerTermsVersion` compile error). `flutter test` shows
the same two pre-existing failures as before this change (that compile error, and
`test/seller_shell_controller_test.dart`'s `NotificationCenter` setup gap) plus the new
`admin_dashboard_controller_test.dart` passing — nothing newly broken. Verified with that new unit
test against the real mock repositories; not click-through-verified in a live browser this session.

**Why:** TODO.md's STATUS table called PHASE 10 "Not started (existing admin screens are
marketplace-era mocks)". That was stale — auditing `lib/modules/admin/` first (before writing
anything, per TODO.md §2/§49's audit-first rule) showed the Overview/Sellers/Sync/Orders/Plans tabs
already call `AdminRepository`/`OrderRepository`/`SubscriptionRepository`/`StoreRepository`, which are
bound to `Firebase*`/`Mock*` implementations exactly like every other module — there was no
marketplace-era mock UI left to replace. What TODO.md §34/§35 actually calls for and was genuinely
missing: a platform financial model that keeps seller GMV separate from Sellora's own revenue ("Do NOT
confuse seller GMV with Sellora revenue"), and any admin visibility into `stores` at all — the
multi-tenant migration (stores/{storeId}/products, .../orders) landed weeks ago but no admin screen
ever read `StoreRepository.allStores()`, despite that method's own doc comment already flagging it for
"admin cross-store oversight later" (`store_repository.dart:5`). PHASE 10 is a 15+ subsystem spec
(users, stores, subscriptions, plans, catalog, orders, fees, payments, refunds, categories, themes,
coupons, reports, support, feature flags, settings); rather than attempt all of it, this session
scoped to the two gaps closest to the seams the app already has real data for, following the same
single-slice-per-session discipline as PHASE 9.

**Changed:**
- **`AdminDashboardController`** (`lib/modules/admin/dashboard/admin_dashboard_controller.dart`)
  rewritten: now also injects `StoreRepository` and `SubscriptionRepository`. Adds `serviceFeeRevenue`
  (sum of `OrderModel.serviceFeeAmount` on paid orders — real against mock data; still 0 against the
  live backend because `functions/lib/orders.js`'s `createOrder` has no seller/fee concept and never
  populates the field, a pre-existing, already-documented gap, not a new bug), `subscriptionMrr` (every
  seller with `hasActiveSubscription == true`, priced at their matched `SubscriptionPlanModel.priceKes`
  — KES-only, deliberately: there's no currency-conversion service yet, PHASE 11 is still not started),
  `subscriptionArr` (`mrr * 12`), `totalPlatformRevenue` (`serviceFeeRevenue + subscriptionMrr`,
  excluding seller GMV on purpose), plus seller-breakdown counts (active/pending/suspended/new-in-30d)
  and a store count. `totalGmv` narrowed to only sum paid orders (was every order regardless of
  payment status).
- **`admin_dashboard_view.dart`** rewritten to match: a "Platform revenue" stat grid (GMV / service-fee
  revenue / subscription MRR / total platform revenue) above the existing "Sellers & stores" grid and
  recent-orders list.
- **New `lib/modules/admin/stores/`** (`admin_stores_controller.dart` + `admin_stores_view.dart`) — a
  read-only, searchable (name/slug/owner) list of every store on the platform via
  `StoreRepository.allStores()`, cross-referenced against `AdminRepository.fetchSellers()` for the
  owner's name/email/status. Tapping a store opens a detail bottom sheet (slug, owner, currency,
  created date). No store-level suspend/activate action — `StoreModel` has no status field, and adding
  one unenforced anywhere would be exactly the "placeholder button that does nothing" TODO.md §54 warns
  against; suspending the owning seller (already wired in the Sellers tab) is the real lever today.
- **`admin_shell_view.dart`/`admin_binding.dart`**: added the Stores tab (6 tabs now). Sellers' icon
  changed from `Icons.storefront_outlined` to `Icons.people_alt_outlined` since Stores now legitimately
  owns the storefront icon.
- **New `test/admin_dashboard_controller_test.dart`**: seeds one paid and one pending-payment mock
  order and asserts GMV/service-fee revenue only count the paid one, MRR matches the mock admin
  repository's one active `growth`-plan seller, and seller/store counts are correct.
- **TODO.md / SELLORA_IMPLEMENTATION_PLAN.md**: PHASE 10 status rewritten to correct the stale
  "not started" framing and record what shipped vs. what's still open.

**Still open (not attempted this session):** store suspension (needs a `StoreModel` status field plus
rules enforcement), refunds UI (server logic exists per PHASE 8's `functions/lib/refunds.js` but has no
`ApiEndpoints` entry or admin screen), coupons, categories, themes, feature flags, platform settings,
reports/support, and churn (needs a historical subscription-state snapshot this session didn't build).

---

## 2026-09-21 — PHASE 9: seller dashboard analytics (first slice)

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as every
recent entry). `flutter test` shows the same two pre-existing failures as before this change
(`test/auth_repository_test.dart`'s missing `sellerTermsVersion` compile error and
`test/seller_shell_controller_test.dart`'s `NotificationCenter` setup gap) — nothing newly broken.
Verified with a widget test against the real mock repositories (seller Home renders every new
section — metrics, sales chart, status breakdown, top products, store health, onboarding checklist —
with no exceptions, and switching the date-range chip recomputes cleanly); not click-through-verified
in a live browser this session.

**Why:** PHASE 9 ("Analytics + marketing") was untouched — the seller Home screen was three static
stat tiles (`seller_dashboard_controller.dart`, pre-change: revenue/listing-count/pending-count) with
no date filtering, no chart, and TODO.md §9's guided-setup checklist never built. Discount codes,
customer analytics, and marketing campaigns are all separate, larger slices of the same phase and
were deliberately deferred rather than attempted alongside this one (see the scoping conversation this
session) — discounts need a new model plus a checkout change, customer analytics needs a `CustomerModel`
that doesn't exist yet, and marketing campaigns have no email/SMS provider wired up to make them real.

**Changed:**
- **`lib/modules/seller/dashboard/dashboard_models.dart`** (new) — `DateRangeOption` enum (Today/
  Yesterday/Last 7/30/90 days/This year/Custom) plus `SalesPoint` and `TopProductStat`, the view's
  chart/top-products aggregates.
- **`SellerDashboardController`** rewritten: fetches the seller's full order/listing history once,
  then derives everything else client-side per selected range — gross sales and net revenue (the
  latter from `OrderModel.sellerRevenue`, the fee snapshot already computed server-side at order
  creation, not re-derived), order count/AOV, a cancelled count, a per-`OrderStatus` breakdown, top
  products by revenue, a sales-over-time series (daily buckets, monthly for "This year"), and a
  percent-change-vs-previous-period delta for sales/orders. `pendingFulfillmentCount` stays
  unfiltered by date range deliberately — it's an operational queue, not a historical metric.
  Store-health fields (`SubscriptionUsageModel` usage, matched `SubscriptionPlanModel`, an
  orders-this-billing-period count) are fetched alongside.
- **Onboarding checklist scoped to only what's real**: TODO.md §9's suggested checklist includes
  "Choose theme," "Add domain," "Configure payment," "Configure shipping" — none of those features
  exist in this codebase yet (no theme system, no domain management, no seller-level payment/shipping
  settings). Showing checkboxes for them would be exactly the "placeholder buttons that do nothing" /
  "claim a feature works when it doesn't" TODO.md itself warns against, so the shipped checklist only
  has the four items backed by real, verifiable state: import a product, publish one, customize the
  storefront (any of `StoreModel`'s tagline/logo/banner/color set — all null at store creation, see
  `auth_repository.dart`'s `_createStoreForSeller`), and make a first sale. The card hides entirely
  once all four are done.
- **`seller_dashboard_view.dart`** rewritten to match: date-range `ChoiceChip` row (+ a custom
  `showDateRangePicker` option), a 6-tile metrics grid with previous-period deltas, an `fl_chart`
  `LineChart` sales-over-time card (single series, brand gold, touch tooltip, an explicit empty state
  instead of a zeroed chart), an order-status breakdown card, a top-products card, a store-health card
  (plan name, listing/order usage bars, taps through to `/seller/subscription`), and the checklist —
  desktop gets the two mid-page cards side by side via `Row`+`Expanded`, not a `Wrap` with
  `SizedBox(width: double.infinity)` (that combination throws — `Wrap` gives unbounded main-axis
  constraints, and an infinite-width child conflicts with them; caught before shipping).
- **`fl_chart: ^0.69.2`** added to `pubspec.yaml` — the package was already named in a "common next
  additions" comment there for exactly this purpose.
- **Fixed a real, pre-existing bug** in `MockOrderRepository.updateStatus`: it rebuilt the order via a
  bare `OrderModel(...)` constructor call that silently dropped `paymentStatus` and the whole fee
  snapshot (`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue`/`paymentFee`) back to their zero
  defaults every time a seller advanced an order's fulfillment status — which would have corrupted the
  exact fields this new dashboard reads for "paid" filtering and net-revenue totals in demo mode. Now
  uses `copyWith(status: status)`, which preserves everything else.

**Not done / open:** discount codes, a `CustomerModel` and customer-level analytics, marketing
campaigns/abandoned-cart/email tooling (all deferred, see "Why" above) — the STATUS table and
`SELLORA_IMPLEMENTATION_PLAN.md` still list these as not started under PHASE 9. No live-browser
click-through this session (verified via widget test instead, see Status above) — a later session
should still eyeball it in Chrome, especially the `fl_chart` sales-chart tooltip and the mobile-width
stacked layout for the status-breakdown/top-products cards.

## 2026-09-20 — PHASE 7: buyer shopping flow unified under `/s/:slug`

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as every
recent entry — `responsive.dart:95`, `mock_admin_repository.dart:49`,
`test/auth_repository_test.dart:63` — none touched by this change). `flutter test` shows the same two
pre-existing failures as before this change (`test/auth_repository_test.dart` — the same missing
`sellerTermsVersion` import above — and `test/seller_shell_controller_test.dart`'s `NotificationCenter`
setup gap, confirmed pre-existing by re-running it against `git stash`); nothing newly broken.
`flutter build web` succeeds. Not click-through-verified in a browser this session — same disclosed gap
as most prior entries.

**Why:** `TODO.md`/`SELLORA_IMPLEMENTATION_PLAN.md` listed PHASE 7 ("Replace the shared buyer feed with
`/s/:slug` storefront pages, store-bound carts, customer profiles beneath that store") as not started,
but that was stale — `StoreScope`, a guest-browsable `StorefrontView` at `/s/:slug`,
`CartRepository.storeId`/`setStore`, `OrderModel.storeId`, and store-scoped
`buyerStoreOrders`/`storeProducts` repository methods already existed (see the 2026-09-11 and
2026-09-13 entries). What was actually missing, per the 2026-09-13 entry's own "Not done" note, was
that cart/checkout was never wired into the public `StorefrontView` — a signed-in buyer still shopped
through a completely separate, flat `/buyer` shell that a guest could never reach, while
`StorefrontView`'s product cards did nothing on tap. Two parallel, duplicate feed implementations
existed side by side: `StorefrontView` (guest, `/s/:slug`, `storeProducts()`) and
`BuyerHomeView`/`BuyerHomeController` (signed-in, flat `/buyer`, `sellerListings()`).

**Changed:**
- **`Routes.storefront` (`/s/:slug`) is now the buyer shell itself** (`BuyerShellView`, bound with both
  `StorefrontBinding()` and `BuyerBinding()`) instead of a standalone `StorefrontView` page — one URL
  serves guests and signed-in buyers alike, so signing in never changes the address.
  `Routes.buyerShell`/`buyerProductDetails`/`buyerCheckout` (flat `/buyer...`) are gone, replaced by
  `Routes.storefrontProduct`/`storefrontCheckout` (`/s/:slug/product`, `/s/:slug/checkout`) — still
  guest-reachable (no `RoleMiddleware`), since a guest can browse a product and hold a cart; checkout
  gates its own submit step in-widget instead.
- **Deleted `lib/modules/buyer/home/`** (`BuyerHomeController`/`BuyerHomeView`) outright —
  `StorefrontView` was already a strict superset (same search/category/grid, plus logo/banner/account
  icon `BuyerHomeView` never had) once its product tap was wired up. `StorefrontView` is now the
  shell's "Shop" tab for everyone; its account icon jumps to the Profile tab in-place
  (`Get.find<BuyerShellController>().changeTab(4)`) when already signed in here, instead of navigating
  to the now-deleted `Routes.buyerShell`.
- **`BuyerShellController`** now resolves `StoreScope` from the route's `:slug` itself
  (`resolveStore()`), mirroring `SellerShellController`'s already-proven pattern exactly — constructor-
  injected deps for testability, same `resolveStore`/gate naming. This is also what calls
  `CartRepository.setStore(store.id)`, now regardless of auth state, so a guest can add to cart before
  ever signing in. **`BuyerShellView`** gates rendering on `scope.isResolving`/`current`/`errorMessage`
  before showing the tab shell, same shape as `SellerShellView`'s guard.
- **`StorefrontController.load()`** simplified: it no longer calls `scope.resolveSlug()` itself (the
  shell now owns that single resolution call) — it just reads the already-resolved
  `scope.current.value`. Fixes a real, if minor, bug along the way: the old version re-resolved the
  slug from scratch on every search keystroke and category tap.
- **Checkout gains a sign-in gate**: `CheckoutView` now renders a "Sign in to complete your order"
  `EmptyState` instead of the order form when the cached user isn't a signed-in buyer of the cart's
  store — closes a real, previously-open gap (`buyerCheckout`/`buyerProductDetails` had no
  `RoleMiddleware` at all, so they were reachable unauthenticated with no guard whatsoever).
  Deliberately no post-login redirect-back to checkout — the buyer's cart survives the sign-in
  round-trip untouched (same store), so they just tap Checkout again from the shop tab. Building
  return-URL plumbing was scoped out.
- **Bug fixed along the way:** `BuyerOrdersController.loadOrders()` left `isLoading` stuck `true`
  forever for a guest (the `user == null` guard returned before setting it false) — a guest on the
  Orders tab saw an infinite spinner. Now clears `orders` and sets `isLoading = false`.
  `BuyerOrdersView`/`BuyerProfileView` both gained a "sign in to continue" `EmptyState` for a guest,
  instead of a stuck spinner or blank name/email fields.
- **`AuthController._goToHome`**'s buyer branch now resolves the buyer's store slug (from
  `Get.parameters['slug']`, already known during sign-in/registration since those happen from
  `/s/{slug}/login`/`register`; falls back to a `StoreRepository.storeById` lookup only for
  `checkSession()`'s cold-start case) and lands on `/s/{slug}` instead of the deleted flat
  `Routes.buyerShell`.
- **`RoleMiddleware`**'s wrong-role redirect for a buyer now points at `Routes.marketing` instead of
  the deleted `Routes.buyerShell` — this branch only fires if a signed-in buyer manually navigates to a
  seller/admin URL, and `redirect()` is synchronous with no cheap way to recover a slug, so this is
  strictly better than the dead reference it replaces rather than a full fix.

**Deliberately not done this pass** (per the plan's scope, to avoid touching work blocked elsewhere):
collections browsing (no model yet — PHASE 5 item), a dedicated `Customer` model or reading
`stores/{storeId}/customers` (nothing reads that mirror doc today), migrating order writes onto
`stores/{storeId}/orders` (the adopted Cloud Functions backend has no store concept server-side at all
— separate PHASE 8 backend work), client-side one-seller-per-cart validation at add-to-cart time (still
relies on the server-side `createOrder` rejection), a multi-store switcher, an order-detail/tracking
screen, and search/SEO improvements beyond what already existed.

---

## 2026-09-20 — PHASE 6: store builder, device photo picker for logo/banner

**Status:** implemented this session. `flutter analyze` clean (same 3 pre-existing issues as the
2026-09-19 entry below — `responsive.dart:95`, `mock_admin_repository.dart:49`,
`test/auth_repository_test.dart:63` — none touched by this change).

**Why:** the branding slice shipped 2026-09-19 only let a seller paste an already-hosted image URL
into the logo/banner fields, which isn't something a real seller has for their own photos. No seller-
side image upload exists anywhere else in the app either (`firebase_storage` is deliberately not a
dependency yet — see pubspec.yaml's "common next additions"), so this needed a way to work without a
storage backend.

**Changed:**
- **`pubspec.yaml`**: added `image_picker: ^1.1.2`.
- **New `lib/core/utils/image_data_url.dart`**: encodes picked image bytes as a `data:<mime>;base64,…`
  URI (`bytesToDataUrl`/`mimeTypeForPath`) and decodes one back to bytes (`decodeDataUrl`, `null` on
  malformed input — same "bad input is just unset" convention as `hexToColor`). `maxPickedImageBytes`
  (350KB) keeps a `StoreModel` update well under Firestore's 1MB document limit, since
  `FirebaseStoreRepository.updateStore` writes the whole model in one `.update()` call.
- **`StoreCustomizeController`**: new `pickLogo()`/`pickBanner()`, backed by a shared `_pickImage`
  helper — `ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024)`,
  rejects anything over `maxPickedImageBytes` with a snackbar, otherwise writes the encoded `data:`
  URI straight into the existing `logoUrlCtrl`/`bannerUrlCtrl` text controllers — `save()` and the URL
  text fields didn't need to change at all, a data URI is just another string in the same field.
  `isPickingLogo`/`isPickingBanner` drive per-button loading state.
- **`StoreCustomizeView`**: an "Upload from device" button under each of the logo/banner fields; the
  URL text field stays too, for a seller who already has a hosted image. `_ImagePreview` now checks
  `isDataUrl()` and renders via `Image.memory(decodeDataUrl(...))` instead of `CachedNetworkImage`
  when the field holds a picked photo rather than a URL.
- **`StorefrontView`**: the buyer-facing logo avatar and banner image do the same `isDataUrl()` check,
  so a picked-from-device logo/banner actually renders on the storefront, not just the editor preview.

**Not done:** no real upload — this inlines the photo as a string rather than storing it in
`firebase_storage`, so a store with both a large logo and banner pushes its `StoreModel` document
size up (bounded to under ~1MB total by `maxPickedImageBytes`, but still far from ideal versus a real
CDN-hosted URL). Moving to actual `firebase_storage` upload is still open, same as it was before this
change — the pubspec.yaml comment on it is unchanged in kind, just narrower in scope. No image
cropping/aspect-ratio enforcement either — a very wide or very tall photo just gets `BoxFit.cover`-ed
into the existing circular/rectangular preview slots, which can crop awkwardly.

**Not verified live in a browser this session** — same caveat as 2026-09-19's entry; analyzer-clean
but no actual click-through of the gallery picker (particularly worth checking on `flutter run -d
chrome`, where `image_picker` uses the browser's native file input).

---

## 2026-09-19 — PHASE 6: store builder, branding slice (retroactive entry)

**Status:** committed (`cc5ae75`, "store builder") but this WORKLOG/TODO/plan update didn't happen in
that session — writing it up now before continuing. Re-ran `flutter analyze` this session: 2 pre-
existing info-level issues (`responsive.dart:95`, `mock_admin_repository.dart:49`) plus one
pre-existing error (`test/auth_repository_test.dart:63`, missing import for the top-level
`sellerTermsVersion` const — unrelated to this commit, not touched by it). No new issues from the
store builder change itself.

**Scope decision:** PHASE 6 per `SELLORA_IMPLEMENTATION_PLAN.md` is theme/section/block/setting
models plus a renderer/preview/publish flow — a large piece of work. This slice is deliberately just
the branding fields `StoreModel` already carries (`name`, `tagline`, `logoUrl`, `bannerUrl`,
`primaryColorHex`) — no new model fields, no sections/blocks, no theme picker beyond a single accent
color.

**Changed:**
- **`lib/core/utils/color_utils.dart`** (new): `hexToColor`/`colorToHex`, tolerant of a missing/
  malformed hex (returns `null` rather than throwing) so an unset store color falls back to the
  default theme color.
- **`Validators.hexColor`** (new, `validators.dart`): only enforces `#RRGGBB` formatting when the
  field is non-empty — the accent color is optional.
- **New `lib/modules/seller/store_customize/`** (`StoreCustomizeController` + `StoreCustomizeView`):
  edits a local copy of the current `StoreScope.current` store's branding fields (5 preset accent
  swatches plus a free-text hex field with inline validation, logo/banner URL fields with a live
  `CachedNetworkImage` preview), saves via the existing `StoreRepository.updateStore` — no repository
  or Firestore-rules changes needed. New route `Routes.sellerStoreCustomize`
  (`/seller/store/customize`), bound in `StoreCustomizeBinding` (added to `seller_binding.dart`),
  registered in `app_pages.dart` behind the same `RoleMiddleware(UserRole.seller)` every other seller
  route uses.
- **`SellerProfileView`**: new "Customize store" list tile above the existing payments tile, opening
  the new screen.
- **`StorefrontView`**: now renders the store's `logoUrl` as an `AppBar` leading avatar, its
  `bannerUrl` as a banner image above the category chip row (both via `CachedNetworkImage`, both
  `SizedBox.shrink()` when unset), and uses `hexToColor(primaryColorHex) ?? AppColors.cargoNavy` for
  the selected-category chip color instead of the hardcoded Cargo Navy — the only three places a
  buyer-facing screen reads store branding today.

**Not started (per `SELLORA_IMPLEMENTATION_PLAN.md` PHASE 6 scope):** theme/section/block/setting
models, a renderer, preview, or publish flow — this is branding-field editing only, not a page
builder. `primaryColorHex` also isn't threaded any further than the one storefront chip row above;
e.g. seller-shell chrome, buttons, and other storefront widgets still hardcode Cargo Navy.

**Not verified live in a browser this session** — picking this up cold from a `/clear`; the change is
small and symmetric with the existing `ManageVariants`/profile screens pattern, but should get an
actual click-through next time this area is touched, per this file's own recurring reminder about
trusting analyzer-clean over browser-verified.

**Next step:** decide whether to keep deepening PHASE 6 (sections/blocks/theme picker) or move to a
different phase — nothing forces the order.

---

## 2026-09-18 — PHASE 5: variants management UI

**Status:** implemented and verified this session (`flutter analyze` clean — same 3 pre-existing
baseline issues as before this session's changes; `flutter test` same 10/12 pass rate; live-verified
in a browser for the seller-side flow). User explicitly picked this slice out of PHASE 5's remaining
list (variants UI, collections, real inventory, SEO fields, bulk ops, pagination, server-authorized
writes) — the rest are still not started, same as the prior entry left them.

**Scope decision:** `ProductVariant` was import-time-only (set once from CJ, never editable after).
Scoped this pass to what's safe to edit without reaching into checkout pricing or the still-unstarted
"real inventory tracking" phase item: a per-variant **enable/disable** switch (which SKUs a buyer can
pick) and a seller-facing **SKU** override. Deliberately did *not* add per-variant price overrides
(would require rewiring `CartItemModel.lineTotal` and the server-side `createOrder` re-pricing logic —
checkout-pricing-engine work, not "management UI") or per-variant stock (that's what PHASE 5's own
"real inventory tracking" item is for — adding a half-version of it here would preempt and conflict
with that session). CJ's own attributes/price/costPrice/image stay read-only — supplier-of-record
facts, not the seller's to edit.

**Changed:**
- **`ProductVariant`** gained `enabled` (bool, defaults `true`) and a `copyWith`; threaded through
  `fromMap`/`toMap`. **`ProductModel.copyWith`** gained a `variants` param (previously impossible to
  update the variant list at all after construction) and a new `visibleVariants` getter — enabled
  variants, falling back to the full list if a seller has disabled every one, so a listing can never
  end up with zero pickable SKUs.
- **New `lib/modules/seller/manage_variants/`** (`ManageVariantsController` + `ManageVariantsView`):
  takes a `ProductModel` via `Get.arguments`, edits a local copy of its variants (toggle
  enabled/disabled, edit SKU), and saves via the existing `ProductRepository.updateListing` — no
  repository or Firestore-rules changes needed, since `updateListing` already writes the whole
  product document. New route `Routes.sellerManageVariants` (`/seller/variants`), bound in
  `ManageVariantsBinding` (added to `seller_binding.dart`), registered in `app_pages.dart` behind the
  same `RoleMiddleware(UserRole.seller)` every other seller route uses.
- **`MyListingsView`**: each listing tile is now an `InkWell` that opens Manage Variants for that
  product (`Get.toNamed(Routes.sellerManageVariants, arguments: product)`); listings with more than
  one variant show a "N variants · tap to manage" hint. The switch keeps its own tap target, so
  toggling listed/unlisted still works independently of the new navigation.
- **Buyer-facing filter**: `ProductDetailsController`/`ProductDetailsView` now read
  `product.visibleVariants` instead of `product.variants` for both the initial variant selection and
  the picker chip row — a disabled variant simply stops being offered to buyers, without deleting it
  or touching the CJ `vid` fulfillment needs.

**Verified live in a browser this session**: `flutter run -d web-server`, driven by a
`playwright-core` script against headless system Chrome (no bundled browser download). Getting a
screenshot out of headless Chrome required `--enable-unsafe-swiftshader` in addition to
`--use-gl=swiftshader`/`--use-angle=swiftshader-webgl` — without it CanvasKit's WebGL2 context never
attaches (`flt-glass-pane` never appears in the DOM) and every screenshot comes back blank white; this
is a headless-Chrome/CanvasKit environment quirk, not an app bug, and is worth remembering for the
next session that needs to drive this app. Signed in as the seller quick-login shortcut
(`seller@test.com`), opened My Listings (3 seeded listings, "Wireless Earbuds" showing its "2 variants
· tap to manage" hint), tapped into it, disabled the "White" SKU, changed its SKU field to
`EARBUD-WHITE-01`, and saved — got the "Variants updated" snackbar and landed back on My Listings with
the listing intact. Zero console errors across every step of the seller-side flow.

**Not verified live:** the buyer-facing consequence (that a disabled variant disappears from the
storefront's variant picker). Jumping to `/s/aminas-picks` in the same page session (needed since the
mock repository is in-memory and per-app-instance, not per-login) reliably hit the same
software-rendering flakiness described above — sometimes a partial render, twice a full blank frame
even after polling for `flt-glass-pane` and waiting several more seconds — and repeating it further
felt like chasing headless-Chrome flakiness rather than the app. The code path itself is small,
symmetric with the already-verified seller-side change, and analyzer-clean:
`ProductDetailsController.onInit`/`selectVariant` and the picker in `product_details_view.dart` both
now read `product.visibleVariants`, the same getter exercised indirectly by
`ManageVariantsController.save()` writing `enabled: false` for the White SKU. Worth a real
browser click-through next time this screen is touched, rather than assumed safe indefinitely.

**Next step:** PHASE 5 still has collections, real inventory tracking, SEO fields, bulk
select/edit/delete, pagination on the unbounded list reads, and server-authorized writes — each needs
its own scoping pass, same as this one.

---

## 2026-09-18 — PHASE 5: `stores/{storeId}/products` write-path migration

**Status:** implemented and verified this session (`flutter analyze` clean — same 3 of the 4
pre-existing baseline issues, confirmed via `git stash` A/B check; `flutter test` same 10/12 pass
rate, confirmed the same way; live-verified in a browser). Closes the blocker
`SELLORA_IMPLEMENTATION_PLAN.md`/`TODO.md` named for PHASE 5: `listProduct`/`updateListing`/
`unlistProduct` wrote flat `listings` while `stores/{storeId}/products` sat rules-ready but always
empty, since nothing wrote to it. User explicitly scoped this session to *just* the write-path
migration — variants management, collections, inventory, SEO, and bulk operations (the rest of
PHASE 5's TODO.md scope) are still not started.

**Found while investigating:** `firestore.rules` already allowed seller-owned create/update on
`stores/{storeId}/products` (lines 101-105) — the "read-only" framing in the prior docs described
the missing application code, not a rules gap. No rules changes were needed for this migration.

**Changed:**
- **`ProductModel`** gained a `storeId` field (nullable — null while sitting in the shared CJ
  catalog, same as `sellerId`), threaded through `copyWith`/`fromMap`/`toMap`.
- **`ProductRepository`**: `listProduct` gained a required `storeId` param; `unlistProduct` now
  takes `(storeId, productId)` instead of just `productId` — both needed to address the new
  subcollection path. `updateListing(ProductModel product)` keeps its old signature since the
  product now carries its own `storeId`.
- **`FirebaseProductRepository`**: `listProduct`/`updateListing`/`unlistProduct` now write
  `stores/{storeId}/products` instead of flat `listings`, using `catalogProduct.id` as the doc id
  directly — the old `${sellerId}_${catalogProduct.id}` cross-seller collision-avoidance key
  (flagged as a wart in every PHASE 4 entry back to 2026-09-14) is no longer needed once each
  seller's products live in their own subcollection. `sellerListings`/`storefrontFeed`/
  `productDetail` were **also** repointed off flat `listings` onto a new `FirestoreService
  .productsGroup` (`collectionGroup('products')`) query — without this, those three reads would've
  kept hitting a collection nothing writes to anymore the moment `useMockData` flips off, which
  would make this a half-migration, not a real one. `storeProducts()` (the customer storefront's
  read path) was already correct and untouched. The flat `listings` getter on `FirestoreService`
  is now dead and removed; `firestore.rules`' `listings` block was deliberately left alone (a rules
  change wasn't required, and removing it is a separate security-pass decision, not bundled here).
- **`firestore.indexes.json`**: added `COLLECTION_GROUP`-scoped field overrides for `products.sellerId`
  /`.id`/`.isListed`, plus a composite `isListed`+`category` index mirroring the existing flat-
  `listings` one — needed for the three collection-group queries above. Unverified against a real
  Firebase project, same caveat as every other backend-shape change in this repo.
- **`MyListingsController.unlist`**: now looks up the listing's own `storeId` before calling
  `unlistProduct` (mirrors `relist`'s existing find-by-id pattern) — no view changes needed.
- **`ProductImportController.import`**: now reads `storeId` from `StoreScope.current.value?.id`
  (already resolved by the seller shell before this screen is reachable) and passes it to
  `listProduct`; bails out (returns `false`) if it's somehow null, same as the existing user/product
  null-guards.
- **`MockProductRepository`**: mirrors the interface change — seeds the two known demo listings with
  their real `store-aminas`/`store-jengo` ids, and its "seed a starter storefront for any other
  seller" fallback now resolves a real storeId via `StoreRepository.storesForSeller` instead of
  leaving it null.
- **`test/mock_subscription_repository_test.dart`**'s fake `ProductRepository` updated to match the
  new signatures.

**Verified live in a browser this session** (same Playwright-driven headless-Chrome approach as
prior sessions — CanvasKit has no queryable DOM, so coordinate clicks + screenshots): signed in as
the seller quick-login shortcut, imported "Wireless Earbuds" (Black, $34.99, publish) — it appeared
in My Listings immediately without leaving the seller shell, exactly as before. Toggled an existing
seeded listing off then on (unlist/relist) — both worked, switch state updated correctly. Opened
`/s/aminas-picks` and confirmed all 3 seeded products still render on the storefront. Zero console
errors across every step tied to this change.

**Found in passing, unrelated to this migration, not fixed:** the storefront's category-chip row
(`storefront_view.dart:86`) trips a "GetX improper use" debug warning — reads an `Obx`-watched value
inside a lazy `ListView.separated` `itemBuilder` rather than in the `Obx`'s synchronous build scope.
Pre-existing (confirmed the file isn't among this session's changes); left alone since it's out of
scope for a product write-path migration.

**Next step:** PHASE 5's write-path blocker is closed. What's left of PHASE 5 per TODO.md §10 —
variants management UI, collections, real inventory tracking beyond the flat `stock` int, SEO
fields, bulk select/edit/delete — is all still open and needs its own scoping pass, same as this
session's.

---

## 2026-09-18 — PHASE 4: category browsing, shipping-cost estimate, buyer variant selector

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing
`info`/`error` issues confirmed present before this session's changes too via a `git stash` A/B
check; `flutter test` same 8/10 pass rate as the pre-existing baseline, confirmed the same way; live-
verified in a browser). Closes the three items the 2026-09-15 and 2026-09-14 entries left explicitly
out of scope: category browsing, a shipping-cost estimate UI, and a buyer-facing variant selector.
All three are additive client-side work — `getCategories`/`calculateFreight` already existed
correctly in `functions/index.js` and `ApiEndpoints`, just with no client consumer yet.

**Changed:**
- **New `lib/data/models/cj_category.dart`**: `CjCategory {id, name}` with
  `topLevelFromRawTree()`, parsing CJ's raw nested category tree (id/name found by key-suffix
  matching, e.g. `categoryFirstId`/`categoryFirstName`) into level-0 nodes only — mirrors
  `functions/lib/catalogSync.js`'s `normalizeCategoryNode`, scoped to a filter chip row rather than a
  3-level drill-down browser.
- **New `lib/data/models/freight_estimate.dart`**: `FreightEstimate {cost, logisticName, currency}`.
  Only `logisticPrice`/`logisticName` are contract-confirmed anywhere in this repo (via
  `functions/lib/orders.js`'s existing consumption of the same CJ call) — no delivery-time field is
  invented.
- **`lib/data/services/cj_dropshipping_service.dart`**: added `getCategories()` (GETs
  `ApiEndpoints.getCategories`, parses via `CjCategory.topLevelFromRawTree`) and `calculateFreight()`
  (POSTs `ApiEndpoints.calculateFreight`, picks the cheapest option by `logisticPrice` exactly the way
  `orders.js` already does server-side at checkout).
- **`ProductRepository`** (+ both implementations, + the test fake in
  `test/mock_subscription_repository_test.dart`): gained `categories()` and `estimateShipping({vid,
  quantity, endCountryCode = 'KE'})`. `FirebaseProductRepository` delegates to the new service
  methods; `MockProductRepository` synthesizes a category list from the distinct `category` names
  already in `MockSeedData.catalog()` and a deterministic per-vid fake freight estimate (~$2.50–$12,
  keyed off `vid.hashCode`) — kept genuinely useful rather than empty stubs, per this repo's "every
  screen fully clickable under `useMockData = true`" rule.
- **`lib/modules/seller/catalog/`**: the catalog browse screen gained a category filter chip row
  (`ChoiceChip`s, toggle-off on repeat tap) above the search field, wired to `browseCatalog`'s
  existing (previously unused) `category` param.
- **`lib/modules/seller/product_import/`**: the Smart Pricing card gained an "Est. shipping to Kenya"
  line and a "Landed cost" (CJ cost + shipping) subtotal; the quick-margin presets and the live
  profit/margin readout now price off landed cost instead of bare CJ cost, matching `TODO.md`'s
  original "CJ cost + Shipping + margin = recommended price" spec. Fetches on initial variant
  selection and every later variant switch (`ProductImportController.selectVariant`). Deliberately
  does **not** touch `ProductModel.costPrice`/`marginPercent` — those stay CJ-cost-only for the
  dashboard and other screens; the landed-cost basis is local to this screen's own calculation.
- **`lib/modules/buyer/product_details/`**: added a variant chip picker ("Choose an option",
  label-only, no price — the buyer always pays `ProductModel.sellPrice` regardless of variant) and
  image-swap state (`previewImage`, this screen had none before). No changes needed to
  `addToCart`/`CartRepository`/`CheckoutController` — the vid/label plumbing through to `OrderItem`
  was already wired from the 2026-09-15 variant-id work; only the picker UI and the `selectVariant()`
  method were missing.

**Verified live in a browser this session**: `flutter run -d web-server` driven by a headless system
Chrome via a small Playwright (`playwright-core`, no bundled browser download) script — same
CanvasKit-has-no-queryable-DOM constraint as the 2026-09-15 session, so coordinate clicks + screenshots
again, not role/label locators. Signed in as the seller quick-login shortcut, opened the CJ catalog:
category chips (Electronics/Fashion/Home) rendered and filtering worked both ways (Home → coffee set +
storage bags; Electronics → earbuds/ring light/laptop stand). Opened the Wireless Earbuds import screen
(2 variants): Black showed CJ cost $14.20 + shipping $3.18 = landed cost $17.38, profit/margin computed
correctly off that ($17.61/101% at the pre-filled $34.99); switching to White updated CJ cost to $15.10
and shipping to a *different* estimate ($11.84, confirming the per-vid mock estimate actually varies),
landed cost/profit/margin recomputed correctly (26.94 / $8.05 / 30%). Then signed in as a buyer at
`/s/aminas-picks/login` and opened the same product from the storefront: a Black/White chip row
appeared, price stayed fixed at $34.99 across both, switching to White swapped the hero image to the
variant's own photo, and "Add to cart" worked (cart badge went 0→1). Zero console errors across every
step.

**Deliberately not done (per the approved plan, out of scope):** category browsing stays level-0 chips
only, not a 3-level drill-down; no buyer-facing shipping estimate (buyer checkout already prices real
freight server-side via `createOrder`); no backend/`functions/` changes (both endpoints already
existed); no title/description/SEO/collections work.

**Caveat, unchanged from the 2026-09-14 entry:** CJ field names beyond `logisticPrice`/`logisticName`
and the id/name key-suffix convention are still unverified against a live CJ account — only backend
tests and `orders.js`'s existing server-side consumption confirm them.

**Next step:** Phase 4's three explicitly-tracked gaps are now closed. What's left of Phase 4 per
`SELLORA_IMPLEMENTATION_PLAN.md` is reconciling how a shared CJ catalog maps onto per-seller `listings`
at scale (still `${sellerId}_${catalogProduct.id}` doc ids) — unchanged from prior entries, not touched
here. Phase 5 (seller product management) remains the natural next phase.

---

## 2026-09-15 — PHASE 4: seller product-import screen (variant picker + smart pricing)

**Status:** implemented and verified this session (`flutter analyze` clean — same 3 pre-existing
`info` lints, `flutter test` 13/13, live-verified in a browser).

Picked up PHASE 4's last-named gap (2026-09-14 entry below, `SELLORA_IMPLEMENTATION_PLAN.md`): the
catalog-browsing plumbing was reconciled with the real backend, but no screen actually used it beyond
a flat-price bottom sheet with a single price field — no variant UI, no images beyond the summary
thumbnail. Asked the user to scope Phase 4's remaining surface (search polish only / full import
experience / full import + categories+shipping); chose "full import experience": a real product-detail
screen plus a margin-based smart-pricing calculator and draft/publish. Explicitly out of scope:
title/description/tags/collections/SEO editing and category browsing/shipping-estimate UI — those need
concepts (collections, SEO slugs) that don't exist anywhere in the app yet.

**Changed:**
- **New `lib/modules/seller/product_import/`** (`product_import_controller.dart`,
  `product_import_view.dart`): replaces the old catalog bottom sheet. `ProductImportController`
  re-fetches the full CJ detail via the existing `ProductRepository.productDetail` (search results are
  summary-only — no description/variants at all, confirmed against `functions/lib/cjApi.js`'s
  `searchProducts`), tracks the selected `ProductVariant`, and prices against that variant's own CJ cost
  (sizes/colors of the same product routinely cost different amounts) rather than always the first one.
  The view shows a real image gallery (main image + thumbnails, swapping to a variant's own photo when
  one is picked), a variant chip picker (only rendered when there's more than one SKU), and a "Smart
  pricing" card: cost price, four quick-margin chips (+20/30/50/100%) that set the price field, and a
  live profit/margin readout recomputed from cost + whatever's in the price field — editable directly,
  not locked to a preset. "Save as draft" / "Publish to store" both call the same `import()`, differing
  only in the `isListed` flag passed through.
- **`lib/data/repositories/product_repository.dart`** (+ both implementations, + the test fake in
  `test/mock_subscription_repository_test.dart`): `listProduct` gained `bool isListed = true` — the
  "save as draft" half of the import workflow needed a way to list unpublished, matching the same
  unpublished state `unlistProduct` already leaves an existing listing in.
- **`lib/modules/seller/catalog/seller_catalog_controller.dart`/`seller_catalog_view.dart`**: the
  controller's `listProduct`/`isListing` (the old bottom-sheet's logic) and the view's
  `_ListProductSheet` are gone — tapping a catalog tile now pushes the new import screen
  (`Get.toNamed(Routes.sellerProductImport, arguments: product)`) instead of opening a sheet with one
  price field.
- **`lib/app/routes/app_routes.dart`**: renamed the long-dead, never-registered `sellerAddListing`
  constant to `sellerProductImport` (`/seller/import`) and actually registered it —
  `lib/app/routes/app_pages.dart` gained the `GetPage` (seller-role-gated, matching every other seller
  route), `lib/modules/seller/seller_binding.dart` gained `ProductImportBinding`.
- **`lib/data/mock/mock_seed_data.dart`**: gave the earbuds (`p1`) and watch (`p2`) mock catalog
  products real sample `ProductVariant`s (distinct per-SKU cost/price, one with its own image) — every
  mock product had zero variants before this, so the variant picker had nothing to demonstrate in demo
  mode. Also fixed three broken Unsplash photo ids that 404'd (`p1`'s intended second image, `p2`'s new
  White-variant image, and `p4`'s long-standing `imageUrl` — the last one predates this session and was
  simply never noticed before, since nothing rendered a coffee-set image next to a working one to
  compare against).

**Bug found and fixed along the way, unrelated to the plumbing above:** `MyListingsController`/
`SellerDashboardController` only call their own `load()` from `onInit()`, but `SellerShellView` builds
all five tabs into one `IndexedStack` up front (see `AdaptiveShellScaffold`) — so both controllers are
created and loaded exactly once, immediately after login, and never again. Importing a product and
switching to "My listings" or "Dashboard" showed stale pre-import data (verified live: a fresh import
didn't appear, and "Active listings" didn't increment) until the whole seller shell was torn down and
rebuilt. Fixed by having `ProductImportController.import()` call `.load()` on both controllers (guarded
by `Get.isRegistered`) right after a successful write — the same self-refresh pattern
`MyListingsController.unlist`/`relist` already use on themselves, just triggered from the sibling screen
that actually changed the data.

**Deliberately not done (out of this pass's confirmed scope):** title/description/SKU/tags editing,
collection assignment, SEO fields — no "collection" or SEO-slug concept exists anywhere in the app yet,
so this would be new modeling, not wiring; category browsing and a shipping-cost estimate
(`getCategories`/`calculateFreight` stay unconsumed `ApiEndpoints`, same as the 2026-09-14 entry left
them — no category-browsing or shipping-estimate UI exists to call them from); a buyer-facing variant
selector (the buyer product-detail page still auto-picks `variants.first`, unchanged from the same-day
vid-wiring entry).

**Verified live in a browser this session**: `flutter run -d web-server` driven by a headless Chrome via
Playwright (system Chrome — Playwright's own browser download has no path to its CDN from this sandbox;
navigated with `networkidle` + coordinate clicks, since Flutter's CanvasKit renderer exposes no DOM for
label/role-based queries, and a `--disable-gpu`/software-rendering launch-flag combination crashed the
page outright, so the plain no-extra-flags recipe was kept). Signed in as the seller quick-login
shortcut and imported the earbuds product: switched Black→White and watched the cost price and gallery
image update reactively without touching the price field, tapped "+30%" and confirmed the price field
became exactly `cost × 1.3`, typed a manual override and watched profit/margin recompute live, then
saved as a draft. Separately published the watch product and confirmed — in the same session, without
navigating away — that "Active listings" on the dashboard went 3→4 and the new row appeared in My
listings switched on, both immediately (the refresh bug above, caught by this exact check). Confirmed a
product with 0/1 variants (Ceramic Pour-Over Coffee Set) skips the variant-picker section entirely
rather than rendering an empty one, and that its draft-saved row shows the toggle off, distinct from the
three active rows. Zero console/page errors across every step.

**Next step:** PHASE 4's app-facing surface now has a real import workflow; what's left of the phase
(per `SELLORA_IMPLEMENTATION_PLAN.md`) is category browsing, a shipping-cost estimate, and reconciling
how a shared CJ catalog maps onto per-seller `listings` at scale (still just
`${sellerId}_${catalogProduct.id}` doc ids) — none of that was in this session's scope. PHASE 5 (seller
product management — editing an existing listing's title/price/variants after import) is the natural
next consumer of this same screen's pricing card.

---

## 2026-09-15 — Fixed buyer-home GetX crash (category chips)

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing
`info` lints, `flutter test` 13/13).

Picked up the loose thread named at the end of the same-day checkout entry below: a fresh buyer
session showed a "[Get] the improper use of a GetX has been detected" red error banner over the
product grid. Reproduced it live (`flutter run -d web-server`, driven by a headless Chrome via
Playwright — pointed at the system-installed Chrome directly, since `npx playwright install`
couldn't reach its CDN from this sandbox) and captured the real stack trace rather than guessing:
the error-causing widget was `Obx` at `buyer_home_view.dart:53`, the category-chips row.

**Root cause:** that `Obx` wraps a `ListView.separated`. `ListView`'s `itemBuilder` is invoked
lazily during layout, *after* the wrapping `Obx`'s own synchronous `build()` has already returned —
so the only reactive read in there (`controller.selectedCategory.value`, used to highlight the
selected chip) never happens inside the Obx's own build scope. GetX's `Obx` throws this specific
error when its first build registers zero observable dependencies, which is exactly what happened:
`controller.categories` is a plain `const List`, not `.obs`, so nothing else in the builder read a
reactive value either. Beyond the crash, this was a real (if less visible) reactivity bug too:
since the dependency was never registered, tapping a category chip would never have re-highlighted
the selection, even if the crash weren't there.

**Changed:**
- **`lib/modules/buyer/home/buyer_home_view.dart`**: the category-chips `Obx`'s builder now reads
  `controller.selectedCategory.value` once at the top of its own scope (before constructing the
  `ListView.separated`), and the `itemBuilder` closes over that captured value instead of
  re-reading `.value` itself. Registers the dependency where GetX can actually see it, fixing both
  the crash and the dead reactivity in one change — no other file touched.

**Verified live in a browser this session**: registered a fresh buyer at `/s/aminas-picks/register`
(mock mode) and landed on buyer home — no error banner, "All" chip highlighted navy by default.
Clicked "Electronics" — chip highlight correctly moved and the grid filtered to the 2 electronics
listings, confirming the reactivity now actually works, not just that the crash is gone.

**Next step:** the two PHASE 4/8 threads named in the entry below are both still open (the seller
variant-picker screen, and the order-model architectural fork). Neither was in this session's scope.

---

## 2026-09-15 — Checkout: real `shippingAddress` shape + `createOrder` response parsing

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds).

Picked up the two items named at the end of the same-day variant-id entry below. Asked the user how to
scope this first, since reading `functions/lib/orders.js` showed the response-parsing half isn't purely
mechanical: the adopted backend has no seller/store/fee concept at all, while `OrderModel` is built
around Sellora's marketplace fee-split (`sellerId`, `storeId`, `serviceFeeRate`, `sellerRevenue`,
`code`). Fixing that "for real" is either a client-side decision to treat those fields as unused/zeroed
bookkeeping (this session's scope), or a bigger change to add seller/store/2% fee support to the backend
itself (named as its own, separate option; not started). User chose the client-only fix.

**Changed:**
- **`lib/data/models/order_model.dart`**: new `ShippingAddress` class (`{countryCode, line}`,
  `fromMap`/`toMap`) — `countryCode` is the only field `createOrder` validates (it derives
  region/currency from it via `functions/lib/regions.js`); `line` is the same free-text address the UI
  collected before. `OrderModel.shippingAddress` is now `ShippingAddress` (was `String`). `copyWith`
  gained a `currency` override — needed because the server derives currency from the shipping address
  and can disagree with the client's draft guess.
- **`lib/data/repositories/firebase_order_repository.dart`**: `placeOrder` now sends
  `order.shippingAddress.toMap()`, and its response parsing reads the real shape
  (`id`/`totalAmount`/`currency`) instead of the nonexistent `orderId`/`code`/`serviceFeeAmount`. There's
  no human-readable order code in this backend, so the order id doubles as `code`. Deliberately keeps
  the client-built `items` list rather than the response's own (which lacks `imageUrl`/`variantLabel`) —
  only the fields the server actually recomputed are trusted from it.
- **`lib/modules/buyer/checkout/checkout_controller.dart`**: `placeOrder` takes a new `countryCode`
  param and builds a `ShippingAddress` from it + the existing address text, used in both the mock- and
  real-mode order construction.
- **`lib/modules/buyer/checkout/checkout_view.dart`**: added a country dropdown above the address field
  (Kenya first, plus US/GB/DE/FR — the countries `functions/lib/regions.js` names its own pricing region
  for; any other country still works, falling back to us/USD region pricing). Wired into `placeOrder`.
- **`lib/core/constants/app_constants.dart`**: `createOrder`'s doc comment updated — both gaps closed;
  documents the one still open (see below).

**Deliberately not done (out of this pass's confirmed scope):**
- No richer CJ-fulfillment address (`fullName`/`phone`/`email`/`line1`/`line2`/`city`/`province`/`zip` —
  what `functions/lib/cjApi.js` actually needs to push a fulfillment to CJ later). `shippingAddress.line`
  stays one free-text field, same shape the UI already collected; only `countryCode` was added.
- No backend change. `sellerId`/`storeId`/`serviceFeeRate`/`serviceFeeAmount`/`sellerRevenue`/
  `paymentFee` on `OrderModel` stay client-side-only bookkeeping the real order doc in Firestore has no
  matching fields for — the 2% platform fee is not actually computed or collected by this backend for
  any order. That's the "add seller/store/fee support to createOrder" option the user didn't pick this
  session.

**Verified live in a browser this session** (not just analyze/test/build): ran `flutter run -d web-server`
and drove it with a headless Chrome via Playwright — signed up a seller, subscribed, signed in as a
buyer at that store's `/s/{slug}/login`, added a seeded product to cart, and placed an order through the
new checkout form. Confirmed the Country dropdown renders (Kenya default, plus US/GB/DE/FR), the order
summary/total render correctly, and submitting produces the "Order placed" snackbar with the order
showing up on the buyer's Orders tab — the mock-mode path works end to end with the new shape.

**Bug found and fixed along the way, unrelated to this change:** `StorefrontLoginView`/
`StorefrontRegisterView` called `_scope.resolveSlug(slug)` synchronously from `initState()`, which flips
`StoreScope.isResolving` (an Rx an `Obx` in the same build depends on) while the widget is still
mid-build — Flutter throws "setState()/markNeedsBuild() called during build" and the page is stuck on
its loading spinner forever. This was a full block on **any** buyer ever signing in or registering at a
storefront, confirmed via a browser console `pageerror`, and would have blocked this session's own live
verification. Fixed in both files by deferring the call with
`WidgetsBinding.instance.addPostFrameCallback`, the standard fix for this class of GetX/Flutter bug —
confirmed fixed by rerunning the same browser flow (the spinner now resolves to the real sign-in form).

**Second, separate bug surfaced but NOT fixed (out of this session's confirmed scope):** the buyer home
screen (`BuyerHomeController`/its view) throws "[Get] the improper use of a GetX has been detected" as a
visible red error banner over the product grid for a freshly-created store's buyer session — the
underlying product data still renders correctly beneath it, and it didn't block navigating to product
details/cart/checkout, so it was left alone rather than pulled into this pass's scope. Worth a dedicated
look next time someone is in `lib/modules/buyer/home/`.

**Next step:** PHASE 8 checkout is no longer blocked on any *named* mechanical gap — what's left is the
real architectural fork flagged above (extend the adopted single-vendor backend with seller/store/2% fee
support, or accept single-vendor and rethink what `OrderModel`'s marketplace fields mean) and the CJ
fulfillment-address shape. For PHASE 4, the seller still has no screen to pick a specific variant before
importing (unchanged from the entry below). The buyer-home GetX error banner above is a loose thread
worth picking up too.

---

## 2026-09-15 — ProductVariant carries CJ's real per-SKU `vid`; threaded through cart/checkout

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds).

Picked up the concrete next step named at the end of the 2026-09-14 entry below: `ProductVariant` was
only `{name, options}` attribute strings, so no real CJ purchasable-SKU id (`vid`) existed anywhere
client-side — the confirmed blocker for both PHASE 4's import screen and PHASE 8's checkout (`createOrder`
requires `{pid, vid, quantity}` per line). Asked the user how to scope this before touching code, given
three genuinely different-sized options (model+wiring only, model+wiring+seller variant-picker screen,
model+wiring+buyer variant-picker screen). User chose the narrowest: model + wiring only, no new UI.

Confirmed the exact real shape against `functions/lib/cjApi.js`'s `getProductDetail` (per variant:
`{vid, sku, key, attributes, image, supplierPriceUsd, retailPriceUsd, weight}` — no per-variant stock;
CJ stock is a separate internal-only lookup used by `catalogSync.js`, not exposed to the client) and
`functions/lib/orders.js`'s `createOrder`/`validateOrderRequest` (every item requires a non-empty
string `vid`, or the request is rejected outright).

Also confirmed neither `product_details_view.dart` nor `seller_catalog_view.dart` ever actually
rendered variant data (the old `selectedVariant` just silently auto-picked "first option" with no
picker UI) — so this really was a pure model/wiring change with zero UI to update, matching the chosen
scope exactly.

**Changed:**
- **`lib/data/models/product_model.dart`**: `ProductVariant` redesigned from `{name, options}` (an
  attribute-picker dimension) to one purchasable SKU: `{vid, sku, attributes: Map<String,String>, price,
  costPrice, image}`, with `label` (e.g. "Black / M"), `fromMap`/`toMap`. `ProductModel.toMap`/`fromMap`
  now round-trip `variants` (previously dropped entirely — a real CJ `vid` would have been lost the
  moment a seller's `listings` doc was written/read back).
- **`lib/data/services/cj_dropshipping_service.dart`**: `_detailToProduct` now maps CJ's real per-SKU
  variant list straight onto `ProductVariant` (`_mapVariants`, replacing the old `_variantOptions` that
  collapsed the list into distinct attribute values and threw the per-SKU `vid` away).
- **`lib/data/models/cart_item_model.dart`**: `selectedVariant` is now `ProductVariant?` (was `String?`).
  Line pricing deliberately still comes from `product.sellPrice` (the seller's own listing price), not
  the variant's CJ price — no pricing-model change was in scope here.
- **`lib/data/repositories/cart_repository.dart`**: `add()` takes `ProductVariant?`; the
  same-product-different-variant cart-line check now compares by `vid` instead of object/string equality.
- **`lib/modules/buyer/product_details/product_details_controller.dart`**: `selectedVariant` is now
  `Rxn<ProductVariant>`, auto-picking `product.variants.first` (unchanged behavior, now the whole variant
  rather than one attribute string).
- **`lib/data/models/order_model.dart`**: `OrderItem` gained `cjProductId` (CJ's `pid`) and split the old
  `variant` string into `variantId` (CJ's `vid`) + `variantLabel` (display). Confirmed zero UI ever read
  `OrderItem.variant` before renaming it.
- **`lib/modules/buyer/checkout/checkout_controller.dart`**: `OrderItem` construction now passes
  `cjProductId`/`variantId`/`variantLabel` from the cart line's product/variant.
- **`lib/data/repositories/firebase_order_repository.dart`**: `placeOrder`'s `createOrder` request now
  sends `{pid, vid, quantity}` per item (previously `{productId, quantity, variant}`, which matched
  neither the adopted backend nor any prior one).
- **`lib/core/constants/app_constants.dart`**: `createOrder`'s doc comment updated — the `vid` gap is
  closed; documents precisely what's still unreconciled (see below).

**Deliberately not done (out of this pass's confirmed scope):**
- No seller-facing variant-picker/import-detail screen and no buyer-facing variant-selector UI — the
  user explicitly chose model+wiring only. A seller importing a multi-variant product still lists it at
  one flat price with whatever `variants` the CJ detail call returned; a buyer's product-detail page still
  silently defaults to the first variant, same as before.
- `FirebaseOrderRepository.placeOrder`'s two other known-broken parts, deliberately left alone rather
  than half-fixed: (1) `shippingAddress` is still a free-text string; `createOrder` requires
  `{countryCode, ...}`, and `CheckoutController` has no UI to collect anything more than a string
  address. (2) The response parsing (`res['orderId']`/`res['code']`/`res['serviceFeeAmount']`) still
  assumes fields the adopted single-vendor backend's `createOrder` doesn't return at all (real shape:
  `{id, totalAmount, currency, items, ...}`, no seller/store/fee concept). Fixing either is a real
  reconciliation of two different checkout models (marketplace-with-fee-split vs. single-vendor), the
  same "reconciling the two backends" work flagged as its own step since the 2026-09-12 backend-adoption
  entry — not a mechanical fix alongside the variant-id wiring.
- `CartItemModel`/checkout pricing still ignores the variant's own CJ `price`/`costPrice` — intentional;
  `sellPrice` is the seller's single chosen price for the whole listing, and changing that would be a
  pricing-model decision, not wiring.

**Next step:** the per-SKU variant id gap is closed at the model layer. What's left for PHASE 8 checkout
to actually work end-to-end against the real backend is exactly the two items above (shippingAddress
shape, response parsing) — both already scoped out here, not newly discovered. For PHASE 4, the seller
still has no screen to actually see/pick a specific variant before importing; today's flat-price import
just carries whichever variants CJ returned along for the ride.

---

## 2026-09-14 — IntasendService reconciled with the adopted backend; deeper checkout blocker confirmed

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints as every prior entry, `flutter test` 13/13, `flutter build web` succeeds).

Picked up from the same day's catalog-plumbing entry below, which flagged `IntasendService`'s three
order-checkout endpoints as "the same class of bug" as the catalog mismatch it had just fixed. Asked the
user how to scope this before touching code, since a first pass at reading the real `payOrderMpesa`/
`payOrderCard`/`confirmIntasendPayment`/`createOrder` contracts (`functions/index.js`,
`functions/lib/orders.js`) showed it isn't actually the same class of bug: the adopted backend's
checkout has no seller/store/fee concept at all, and `createOrder` requires CJ's own `pid`/`vid` per
line item — a purchasable per-SKU id that doesn't exist anywhere client-side (`ProductVariant` is only
`{name, options}` attribute strings, confirmed in the same-day catalog entry). Fixing
`FirebaseOrderRepository.placeOrder` for real is therefore blocked on the same variant-id gap as PHASE
4's import/variant-picker screen — not a same-day fix. User chose the narrow option: fix
`IntasendService` itself (mechanical, self-contained) and explicitly leave `placeOrder`/
`CheckoutController` documented as still broken, rather than either stopping entirely or wiring a
placeholder `vid` through checkout just to make it "run."

**Changed:**
- **`lib/core/constants/app_constants.dart`**: replaced `intasendCollectMpesa`/`intasendCheckout`/
  `intasendStatus` with the real `payOrderMpesa`/`payOrderCard`/`confirmIntasendPayment` endpoint
  constants; expanded the `createOrder` doc comment with the specific `pid`/`vid` blocker found this
  session (previously it only said "old shape," not why that shape can't just be swapped in).
- **`lib/data/services/intasend_service.dart`**: rewritten. `collectMpesa`/`createCheckout`/
  `checkStatus` (client-computed amount, generic "reference") replaced with `payOrderMpesa(orderId,
  phoneNumber)` / `payOrderCard(orderId, method, redirectUrl)` / `confirmOrderPayment(orderId)` —
  matching the real contract, where the server derives the amount from an order it already created and
  every call keys off that order's id, not a client-supplied figure. `checkStatus` was a GET; the real
  endpoint (`confirmIntasendPayment`) is a POST that also fulfills the order server-side when complete,
  so the new `confirmOrderPayment` reflects that too. Removed the now-fully-unused `PaymentResult` class
  (only ever constructed by the two rewritten methods).
- **`lib/modules/buyer/checkout/checkout_controller.dart`**: updated its one call site
  (`collectMpesa(phone:, amountKes:, narrative:)` → `payOrderMpesa(orderId:, phoneNumber:)`) so the
  project keeps compiling, and expanded the surrounding comment to say plainly that this whole branch is
  unreachable today (`useMockData` is always true) and would still fail if it ran, because `placeOrder`
  above it sends the old request shape and has no real CJ `vid` to send. The `payOrderMpesa` call itself
  is now correct; what it would be called with isn't, yet.

**Deliberately not done (out of this pass's confirmed scope):** `FirebaseOrderRepository.placeOrder`'s
request/response shape and `createOrder`'s missing seller/store/fee concept — reconciling either for
real needs a variant-id-carrying product model first (PHASE 4's still-unstarted import/variant-picker
screen), not a client-side endpoint fix. `createCheckout`/`payOrderCard` (card/Google Pay) has no caller
anywhere in `lib/` today, same as before — left in place as correctly-shaped but unconsumed, matching
`getCategories`/`calculateFreight`'s status.

**Next step:** checkout end-to-end is now blocked on one concrete, named thing — a real per-SKU variant
id reaching the cart/order — rather than a vague "Phase 8 scope" note. Whoever next works on either
PHASE 4's import/product-detail screen or PHASE 8's checkout should treat those as the same unblocking
step, not two independent ones.

---

## 2026-09-14 — PHASE 4 started: CJ catalog-browse plumbing reconciled with the adopted backend

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints as every prior entry, `flutter test` 13/13, `flutter build web` succeeds). No new test coverage
added for `CjDropshippingService` itself — flagged below as a real gap, not silently skipped.

Picking up PHASE 4 (catalog + CJ import), repeatedly flagged since the 2026-09-12 backend-adoption
entry as "the real next step": the Flutter client's `ApiEndpoints`/`CjDropshippingService`/
`ProductModel` parsing were still written against the *old*, deleted TypeScript backend and didn't
match the adopted `functions/index.js` at all — wrong endpoint names, wrong query param names, and no
awareness of the `{success, data, message}` response envelope every endpoint in the adopted backend
uses. Confirmed with the user beforehand to scope this pass to catalog-browsing plumbing only (search,
detail, admin sync) — not the checkout/payment path, and not any new UI.

An `Explore` audit first read every relevant file on both sides (`functions/index.js` in full, plus
`cjApi.js`/`catalogSync.js`/`pricing.js`/`marginPricingService.js`/`fx.js`/`regions.js` on the backend;
`ApiEndpoints`, `CjDropshippingService`, `ProductModel`, both `ProductRepository` implementations, and
their controllers on the client) and produced a field-by-field diff before any code changed.

**What the audit found, beyond the wrapper mismatch:**
- `ApiEndpoints.cjSearchProducts`/`cjProductDetail`/`cjCreateOrder`/`cjTrackShipment` don't exist as
  exported functions at all; the real names are `searchProducts`/`getProductDetail`. `createFulfillmentOrder`/
  `trackShipment` in `CjDropshippingService` were dead code (zero callers) that also didn't match any real
  endpoint shape.
- `searchProducts`'s live response has no `stock`/`rating`/`soldCount`/`discountPercent`/`compareAtPrice`/
  `currency` — `ProductModel.fromMap` was reading all of those from a shape that can never supply them.
- `getProductDetail` has no top-level price or stock at all — pricing lives per-variant; the real
  variant shape (`{vid, sku, key, attributes, image, supplierPriceUsd, retailPriceUsd, weight}`) has no
  overlap with `ProductVariant`'s existing `{name, options}` attribute-picker shape, so
  `ProductModel.variants` was always `[]` regardless of what the backend returned.
- `FirebaseAdminRepository.syncCjCatalog()` hand-rolled its own partial sync from the client (one page
  of `searchProducts`, no categories/detail/variant/stock enrichment) and batch-wrote into a Firestore
  collection named `catalog` — which the backend's real sync pipeline (`runCatalogSync`,
  admin-claim-gated, up to 9 minutes) never touches; it writes `products`/`categories` instead. Two
  independently-invented, non-overlapping collection names for the same concept, and the client path
  bypassed the admin-claim gate entirely.
- No seller/store field exists anywhere on the backend's catalog responses or Firestore docs — confirmed,
  matches the 2026-09-12 entry. This is a real, load-bearing gap for PHASE 4/5 (mapping a shared catalog
  onto per-seller listings has no backend hook to lean on), not something this pass could fix.
- A second, unrelated stale-endpoint bug surfaced while cross-checking `ApiEndpoints`: `intasendCollectMpesa`/
  `intasendCheckout`/`intasendStatus` (used by `IntasendService`, the buyer-checkout payment path — PHASE 8,
  not this pass) also don't match anything the adopted backend exports (real names are
  `payOrderMpesa`/`payOrderCard`/`confirmIntasendPayment`). Left alone and flagged inline in
  `app_constants.dart` rather than fixed, since it's checkout/payment code deserving its own confirmed
  pass, not catalog-browsing. Same for `FirebaseOrderRepository.placeOrder`/`createOrder`'s request/
  response shape, which is likewise still written against the old deleted backend.

**Changed:**
- **`lib/core/constants/app_constants.dart`**: replaced the four wrong CJ endpoint names with the real
  ones (`searchProducts`, `getProductDetail`, `getCategories`, `calculateFreight`, `runCatalogSync`);
  added inline notes flagging the `createOrder`/IntaSend-checkout staleness found above for whoever picks
  up PHASE 8.
- **`lib/core/network/dio_client.dart`**: `post()` gained an optional `receiveTimeout` override — the
  default 20s would always time out `runCatalogSync`, which can legitimately run for minutes.
- **`lib/data/services/cj_dropshipping_service.dart`**: rewritten. `searchProducts`/`productDetail` now
  call the correct paths with the correct query param names (`categoryId` not `category`, `pid` not
  `id`, plus `size`), unwrap `data` themselves (matching the pattern `FirebaseSubscriptionRepository`
  already established for `subscribeSeller` — no `success` boolean check needed since a `success:false`
  response always carries a non-2xx status, which `DioClient` already turns into a thrown
  `ApiException`), and map the real field names onto `ProductModel` via new private
  `_summaryToProduct`/`_detailToProduct` helpers instead of relying on `ProductModel.fromMap` (deliberately
  left untouched — it's the round-trip shape for the client's own persisted `listings` documents, a
  different concern from parsing the backend's raw catalog response). Added `_variantOptions` to derive an
  attribute-picker from the real per-SKU variant list (distinct values per attribute name) — the closest
  a `{name, options}` shape can get to real variant data without a model change. Added `runCatalogSync()`.
  Removed dead `createFulfillmentOrder`/`trackShipment`.
- **`lib/data/repositories/firebase_admin_repository.dart`**: `syncCjCatalog()` now calls
  `CjDropshippingService.runCatalogSync()` instead of hand-rolling a partial sync and batch-write;
  interface (`Future<int>`) unchanged so `AdminCatalogSyncController` needed no changes.
- **`lib/data/services/firestore_service.dart`**: removed the now-fully-unused `catalog` collection
  getter (confirmed zero remaining references after the above).
- **`firestore.rules`**: removed the stale `catalog/{productId}` block, which referenced a
  `syncCjCatalog` Cloud Function that no longer exists in that form. Left `products`/`categories`
  (the real, server-written collections) with no explicit client rule — default-denied, matching that
  nothing in `lib/` reads either directly today (catalog browsing goes through the HTTP endpoints, not
  Firestore reads); noted inline for whenever that changes.

**Deliberately not done (out of this pass's confirmed scope):**
- `getCategories`/`calculateFreight` are wired up as `ApiEndpoints` constants (accurate names for
  whenever they're needed) but have no `CjDropshippingService` methods yet — nothing in `lib/` consumes
  either today (no category-browsing UI, no shipping-estimate UI), so adding client methods now would be
  speculative.
- No dedicated "recalculate price for margin X" endpoint exists anywhere server-side — margin pricing
  (`pricing.js`/`marginPricingService.js`) is baked silently into `retailPriceUsd` inside search/detail
  responses with no way to ask "what if I set margin to Y%". If PHASE 4's import-editor screen wants an
  interactive margin slider, that needs a new backend endpoint, not a client fix.
- The IntaSend order-checkout path and `FirebaseOrderRepository.placeOrder`'s shape (flagged above) —
  real bugs, same class as the ones just fixed, but PHASE 8 scope, not this pass.
- Reconciling how a shared, unscoped CJ catalog maps onto per-seller `listings` at import time — the
  plumbing this pass fixed makes that possible to build correctly, but no import-editor UI exists yet
  (`SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 4 section, still not started as app-facing work).

**Verification gap, disclosed:** no test exercises `CjDropshippingService`'s new parsing logic directly
(mocking `DioClient`/Dio) — relied on `flutter analyze`/`flutter test`/`flutter build web` staying clean,
which only proves the code compiles and every *other* code path is unaffected, not that the new mapping
is correct against a live response. Also unverified against a real deployed `functions/index.js` — same
"never run against real backend" caveat as every prior entry (`useMockData` is still `true`).

**Next step:** PHASE 4's remaining app-facing work (a catalog browse/import screen actually using this
now-correct plumbing) is still not started. PHASE 8's stale checkout-payment endpoints, found but not
fixed here, are the next concrete gap if payments work resumes before catalog import screens do.

---

## 2026-09-14 — Role select returns for mobile, seller-only this time

**Status:** implemented and verified this session (`flutter analyze` clean — same 4 pre-existing `info`
lints as every prior entry, `flutter test` 13/13). No browser-driven check — same disclosed gap as
every prior entry.

User asked for the platform split to be explicit: mobile app leads splash → role select → sign in; web
leads with the marketing view. Web already worked this way (`SelloraApp.initialRoute` picks
`Routes.marketing` under `kIsWeb`) — the actual gap was mobile, where `AuthController.checkSession()`
sent an unauthenticated visitor straight to `Routes.marketing` too, skipping role select entirely
(a deliberate choice made in the entry directly below, before this one).

Re-adding role select isn't a plain revert: the version deleted on 2026-09-13 offered two cards, "Shop
the marketplace" (buyer) and "Start selling" (seller), because buyers were still a shared top-level
role back then. Today a buyer only exists as a customer of one store, signed in from that store's own
`/s/{slug}/login` — there's no top-level buyer destination to point a card at, and no store-directory
screen exists yet for a mobile user without a direct link to find one. Confirmed with the user: keep
role select seller-only for now (a welcome step with "Start selling" → `registerSeller` and "Sign in" →
`login`) rather than also building a new store-search screen to restore the buyer card.

**Changed:**
- **New** `lib/modules/auth/views/role_select_view.dart` — reintroduced, trimmed to the single seller
  card plus "Already have an account? Sign in" and "Learn more about Sellora" links. No `intent`
  argument passed anywhere (today's `LoginView` doesn't branch on one).
- **`lib/app/routes/app_routes.dart`**: added `Routes.roleSelect = '/role-select'`.
- **`lib/app/routes/app_pages.dart`**: registered the route (no binding needed — the view has no
  controller).
- **`lib/modules/auth/controllers/auth_controller.dart`**: `checkSession()`'s no-session branch is now
  `kIsWeb ? Routes.marketing : Routes.roleSelect` instead of unconditionally `Routes.marketing`.
- **`lib/main.dart`**: updated the `initialRoute` comment to describe the full mobile chain.

**Still open:** a buyer with no direct `/s/{slug}` link has no way to find a store from the mobile app —
flagged above as a real gap, not fixed here since the user chose to scope this to the seller-only
welcome step.

---

## 2026-09-14 — Claude Design "Meridian" export reviewed; documented as reference-only, not a build spec

**Status:** documentation only — no Flutter or Cloud Functions code changed.

A Claude Design project ("Sellora Mockups," `_ds/sellora-meridian-design-system-ffa880f5-…`) was shared
for import via the `claude_design` MCP: design tokens (`tokens/*.css`), React recreations of Meridian's
component set, and three click-through portal UI kits (`ui/{admin,buyer,seller}/{bundle.jsx,mockData.js}`)
plus browser/iOS frame chrome for prototyping outside Flutter. Read every listed file before deciding
what, if anything, to bring into the app.

**Findings:**
- The project's own `readme.md` says it was built by reading `lib/app/theme/` and the existing screens
  directly — it's an export *of* the app, not a design *for* the app. Confirmed: `colors.css`,
  `spacing.css`, `radius.css` are value-for-value identical to `AppColors`/`AppSpacing`/`AppRadii`
  (`lib/app/theme/app_colors.dart`, `app_metrics.dart`).
- Every screen in the three `bundle.jsx` files already exists as a Flutter module: seller's
  dashboard/catalog/my_listings/orders/profile/subscription, admin's
  dashboard/sellers/catalog_sync/orders/plans, buyer's home/product_details/cart/checkout/orders/profile
  all have a matching directory under `lib/modules/`.
- The project's auth-flow description ("splash → role select → sign in / register") is now stale: the
  2026-09-13 entry below deleted `role_select_view.dart`/`register_buyer_view.dart`/`store_select_view.dart`
  as part of the multi-tenant storefront rework. The design project predates that change and still shows
  the old shared-marketplace role picker, not today's seller-only `/login` + per-store `/s/{slug}/login`.

**Decision (confirmed with the user):** treat this as an external reference for prototyping, marketing
collateral and decks outside Flutter — not an implementation spec. Reimplementing its screens in Flutter
would rebuild what already exists, and its buyer/auth screens would reintroduce flows deleted this week.
Same category of mistake as the 2026-09-06 marketplace-layer drop that was evaluated and deleted earlier
(not logged in this file, but on record): treat the repo, not an externally-authored artifact, as the
source of truth. No code was changed as a result of this review.

**Still open:** the design project itself hasn't been corrected (its readme and auth mockups remain
stale) — if it's kept as a living reference, a follow-up push via `DesignSync` to update the auth screens
and note the storefront-per-seller model would keep it useful; not done this session since it wasn't
requested.

---

## 2026-09-13 — Sellora's own login becomes seller-only; buyer auth moves into the storefront

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 13/13, `flutter build web` succeeds). No browser-driven check — same disclosed
gap as every prior entry (no `chromium-cli`/Python in this environment); see "Verification gap" below.

Closed the gap between the multi-tenant data model (already built — see the 2026-09-11 entries) and
Sellora's own auth flow, which still had a full buyer path living at the top level. Auditing first
found most of the *data model* already done: `StoreModel`/`StoreRepository` (abstract+mock+Firebase),
`StoreScope`, a guest-browsable `StorefrontView`, and `firestore.rules`' `stores/{storeId}/{customers,
products,orders}` rules all already existed and needed no changes. What was actually missing was the
auth wiring: `RoleSelectView` still offered "Shop the marketplace," `RegisterBuyerView`/`StoreSelectView`
were reachable from Sellora's own top-level flow instead of from inside a store's own URL, and both
buyer/seller profile screens had hardcoded shortcuts into the other role's login. Confirmed with the
user beforehand: delete `StoreSelectView` outright rather than repurpose it as a store directory — its
own code comment already called it a stand-in "until path routing (`/s/:slug`) exists," which now does.

**A real bug found and fixed along the way:** `MockAuthRepository.signIn`'s buyer branch never set
`storeId` at all — every mock buyer sign-in silently got `storeId: null`, breaking
`CartRepository.setStore`/`BuyerOrdersController`'s store-scoped queries for anyone using the generic
mock sign-in shortcut (not just this session's new store-scoped login path).

**Changed:**
- **Deleted** `lib/modules/auth/views/role_select_view.dart`, `register_buyer_view.dart`,
  `store_select_view.dart`, `lib/modules/auth/controllers/store_select_controller.dart`. Removed
  `Routes.roleSelect`/`registerBuyer`/`storeSelect` and their `GetPage`s.
- **`lib/modules/auth/views/login_view.dart`** rewritten as the sole entry point (`Routes.login`
  replaces the old role-chooser) — seller/admin only, no `intent` branching. Split-screen layout on wide
  screens (a marketing panel — wordmark, headline, one testimonial, three trust badges, all copy reused
  from existing `MarketingView` claims — next to the sign-in form), form-only below the desktop
  breakpoint. Modeled on a generic single-purpose SaaS login pattern; the `app.droxen.cloud/login`
  reference the user linked 403'd on fetch, so this wasn't built against the actual page — flagged to
  the user to compare and redirect if the shape is off.
- **New** `lib/modules/storefront/storefront_login_view.dart` / `storefront_register_view.dart` — a
  buyer's sign-in/registration as a customer of one store, reached only at `/s/{slug}/login` and
  `/s/{slug}/register` (`Routes.storefrontLogin`/`storefrontRegister`), storeId resolved from the route
  `:slug` via `StoreScope` rather than passed as `Get.arguments`. `StorefrontView` gained an account
  icon in its `AppBar` linking here (or straight to `/buyer` if already signed in as *this* store's
  buyer).
- **`AuthRepository.signIn`** gained an optional `storeId` param (`FirebaseAuthRepository` ignores it —
  a real buyer's doc already carries their true storeId; `MockAuthRepository` uses it to fix the bug
  above). **`AuthController`** gained `signInToStore` (rejects a sign-in whose result isn't a buyer of
  exactly that store — signing in from the wrong store's page can't silently attach the wrong
  cart/order history) and taught `signIn` to reject a buyer-role result outright, so Sellora's own login
  can't be used as an accidental side door into the buyer portal.
- Removed the cross-role shortcuts: `BuyerProfileView`'s "Become a seller" tile, `SellerProfileView`'s
  "Shop as a buyer" tile (neither makes sense once a buyer belongs to one specific store). Buyer
  sign-out (`BuyerProfileView`) now resolves the buyer's store slug and returns them to `/s/{slug}`
  instead of Sellora's own login, falling back to `/marketing` if the store can't be resolved.
  `RoleMiddleware`'s unauthenticated fallback now splits by role: buyer → `/marketing` (no store context
  to send them anywhere store-specific), seller/admin → `/login`.
- `MarketingView`: removed the buyer sign-in CTA and the footer's "Shop the marketplace" link — no path
  from marketing into a buyer flow through Sellora's own auth.

**Not done:** cart/checkout still isn't wired into the public `StorefrontView` itself (same deliberate
deferral its existing code comment already stated) — a buyer still completes shop→cart→checkout via the
existing flat `/buyer` shell after signing in, same as before this session. No `firestore.rules` or
`firestore.indexes.json` changes were needed — verified the existing tenant-scoped rules and the
unfiltered/single-field-sorted store subcollection reads already cover this without a new composite
index.

**Verification gap, disclosed:** did not drive this through an actual browser — same environment gap
noted in the 2026-09-11 entries (no `chromium-cli`, no Python). Relied on `flutter analyze`, `flutter
test` (13/13, including a fixed `test/seller_shell_controller_test.dart` fake that needed the new
`signIn` param), and a clean `flutter build web`. Worth a manual click-through (seller login → dashboard;
`/s/aminas-picks` and `/s/jengo-electronics` → account icon → sign in → confirm separate carts/order
history per store; buyer sign-out lands back on the right store) before this is considered fully proven.

**Next step:** none of this touches `functions/` — the adopted backend still has no seller/store concept
at all (see the 2026-09-12 backend-adoption entry), which remains separate, larger work.

---

## 2026-09-12 — PHASE 3 (Billing): security core, configurable plan schema, usage tracking

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 13/13, `cd functions && npm test` 227/227, `cd firestore-tests && npm test`
18/18). Builds on the same-day backend adoption entry below — read that first.

Closes the gap both this file and `SELLORA_IMPLEMENTATION_PLAN.md` had flagged since 2026-09-11:
`FirebaseSubscriptionRepository.subscribeSeller` wrote `billing_history`/`users` subscription fields
directly from the client, which `firestore.rules`' `allow write: if false` on `billing_history` already
silently blocked against real Firestore. Confirmed scope with the user beforehand: security core +
configurable plan schema + usage tracking, keeping the existing Starter/Growth/Scale pricing and
per-plan commission unchanged.

**Data model:** `SubscriptionPlanModel` gained `orderLimit`/`storeLimit`/`features` (backward-compatible
defaults, `copyWith` added) — `storeLimit` is schema-only/unenforced pending decision #4 (multi-store),
`orderLimit` is schema-only/unenforced because `createOrder`'s backend has no `sellerId` to count
against yet (see the backend-adoption entry). New `SubscriptionRecordModel` (`subscriptions/{sellerId}`,
read-only from Dart) and `BillingHistoryEntryModel` (`billing_history/{id}`) — both written only by
Cloud Functions. New `SubscriptionUsageModel` (listing usage only; no order-count fields for the same
reason `orderLimit` isn't enforced). `AuthRepository` gained `refreshCurrentUser()` — re-reads the
user doc bypassing the in-memory cache, since activation is now server-side and the client has no
realtime channel to it.

**Cloud Functions:** new `functions/lib/subscriptions.js` — `createBillingEntry` (server-prices from
`subscription_plans`, writes a pending ledger entry), `activatePendingSubscription` (idempotent —
guards on `isPayable`/entry status — upserts `subscriptions/{sellerId}` and mirrors
`subscriptionPlanId`/`subscriptionActiveUntil`/`sellerStatus` onto `users/{sellerId}` in one batch),
`attachBillingPaymentAttempt`/`billingRefMatches` (the anti-fraud invoice-binding check, mirroring
`orders.js`'s `paymentRefMatches` — without it, a genuinely-completed IntaSend invoice for a *different*
payment could be paired with someone else's billing entry id and activate their subscription for free).
`functions/index.js` gained `subscribeSeller`, `payBillingMpesa`, `payBillingCard`,
`confirmBillingPayment` — exact structural mirrors of the existing order-payment handlers, reusing
`intasend.mpesaStkPush`/`createCheckout`/`checkPaymentStatus`/`verifyAmount` completely unchanged.
`intasendWebhook` now checks `billing_history` before falling through to the existing order lookup (order
ids and billing entry ids can never collide — separate collections, separate auto-ids). New
`functions/test/subscriptions.test.js` (9 cases) covers `isPayable`/`billingRefMatches` as pure
functions, matching this codebase's existing test style.

**Firestore rules:** new `subscriptions/{sellerId}` block (owner-or-admin read, `write: if false`).
`users/{uid}`'s update rule extended with a field-level lockdown via
`request.resource.data.diff(resource.data).affectedKeys()` blocking self-writes to
`subscriptionPlanId`/`subscriptionActiveUntil`/`sellerStatus` — the same technique already used to lock
down `role`, closing the hole where a seller could self-activate by editing their own user doc.
`create` stays unrestricted (signup legitimately sets `sellerStatus: pendingApproval`). New
`firestore-tests/billing-hardening.test.js` (7 cases).

**Repositories:** `SubscriptionRepository.subscribeSeller` no longer takes a client-supplied
`paymentReference` — it returns a pending `BillingHistoryEntryModel`; added `fetchUsage`.
`FirebaseSubscriptionRepository` now injects `DioClient`, posts to the new endpoints, and no longer
writes `_fs.users`/`_fs.billingHistory` directly at all (the actual fix). `MockSubscriptionRepository`
now injects `AuthRepository` and activates the mock user itself inside `subscribeSeller` — this is what
let the hand-rolled `UserModel` reconstruction duplicated in both `SellerOnboardingController` and
`SellerSubscriptionController` be deleted entirely, real mode's copy of which also had to go regardless
since the new rules block it.

**Controllers/UI:** `SellerOnboardingController` gained an `OnboardingStep.pendingConfirmation` step and
`refreshStatus()` — in mock mode nothing changes (repository already activated synchronously); in real
mode, payment is fired via `payBillingMpesa` and the screen shows a pending state with a manual "I've
completed payment" refresh action, since there's no live confirmation channel (matching buyer checkout's
own fire-and-forget standard — deliberately not introducing polling/streaming here). `switchPlan` on
`SellerSubscriptionController` gained the identical pattern plus a try/catch it was missing before (a
real pre-existing bug — an exception there previously propagated unhandled). `SellerSubscriptionView`
gained a "Usage this period" listing-count card and a "Refresh status" action. `AdminPlansController`/
view gained order/store-limit and feature-flag editing (schema-only, left visibly editable rather than
hidden). `SellerCatalogController.listProduct` gained a soft, client-side listing-limit upsell check —
deliberately not server-enforced, since listing creation isn't server-authoritative yet (Phase 5).

**Not done (deliberately deferred, not silently skipped):** order-limit enforcement inside `createOrder`
and order-usage display — both need `sellerId` on the order document, which the newly-adopted backend's
`orders.js` doesn't have (see below); store-limit enforcement — gated on decision #4; a full billing UI
(invoices list, cancel/resume, plan-comparison) — out of the confirmed scope for this pass.

**Next step:** PHASE 4/5/8's reconciliation of the adopted backend with the Flutter client's
`ApiEndpoints`/`ProductModel`/order shapes is what unblocks the deferred items above.

---

## 2026-09-12 — Cloud Functions backend replaced (rebranded from a dropped-in codebase); Phase 3 started

**Status:** in progress this session, picking up from "let's go to phase 3" (billing).

Before Phase 3 work could start, found `functions/` in an inconsistent state: the tracked Sellora
TypeScript functions (`auth.ts`, `cj.ts`, `index.ts`, `intasend.ts`, `orders.ts`, `tsconfig.json`) were
deleted, uncommitted, and replaced on disk by an untracked plain-JavaScript codebase from a different
project, "GoShopping" (a single-vendor CJ dropshipping storefront — `functions/package.json`'s own
description said so). Confirmed with the user this was deliberate: keep it, rebrand it, and **fold its
capabilities into Sellora's existing multi-tenant architecture** rather than restore the old TS code or
pivot Sellora to single-vendor.

**What the adopted codebase actually is** (a strict superset of what it replaces, once rebranded): a
real CJ auth/token-refresh/catalog-sync/tracking pipeline (`cjAuth.js`, `cjApi.js`, `catalogSync.js`,
`tracking.js`) well beyond the old `cj.ts` sketch; a margin-based Smart Pricing Engine with FX and
region/VAT handling (`marginPricingService.js`, `pricing.js`, `fx.js`, `regions.js`); IntaSend *and*
PayPal (`intasendApi.js`, `paypalApi.js`), with real provider-side refunds (`refunds.js`); product
reviews with a transactionally-updated rating aggregate (`reviews.js`); a per-instance LRU/TTL cache
(`cache.js`); and a 218-case `node --test` suite covering the pure logic in all of it. Auth is the same
shape as before — `Authorization: Bearer <idToken>` verified via `admin.auth().verifyIdToken`.

**The real gap, not fixed this session:** this codebase has **no seller/store concept anywhere** — one
global `products` catalog, one global `orders` collection, no `sellerId`/`storeId` on anything —
whereas Sellora's own multi-tenant work (`stores/{storeId}/...`, `StoreScope`, per-seller `listings`,
the 2% marketplace fee split) assumes many sellers each running a store. `orders.js` and everything
hung off it (`payOrderMpesa`/`payOrderCard`, `confirmIntasendPayment`, `intasendWebhook`, `refundOrder`,
`submitProductReview`'s verified-purchase check) has no seller/store attribution or fee split. The
Flutter client's current `ApiEndpoints`/`ProductModel.fromMap`/`FirebaseOrderRepository`/
`CjDropshippingService` also don't match this backend's request/response shapes at all — it wraps
every response as `{success, data, message}`, not the old flat fields, and uses different field/query-
param names throughout. Reconciling per-seller order/catalog attribution with this backend is separate
future work (Phase 4/5/8 territory) — not attempted here. Since `AppConstants.useMockData` is still
`true` and the app has never run against real Firebase, none of this is a regression from a working
state; it's a disclosed gap in scaffolding, same as every other "Not started" line in
`SELLORA_IMPLEMENTATION_PLAN.md`.

One more unreconciled duplicate: admin gating in this codebase is a Firebase Auth custom claim
(`user.admin === true`), while the rest of Sellora checks a Firestore `users/{uid}.role` field. Not
fixed here — flagging so a later session doesn't assume Sellora's existing admin accounts can call
`refundOrder`/`runCatalogSync`.

**Changed:**
- `functions/lib/orders.js` — the one substantive rename (`GoShopping order ${orderId}` → `Sellora
  order ${orderId}`, a CJ order remark string). This and `functions/package.json`'s `description` were
  the *only* two "GoShopping" strings anywhere in the adopted code — confirmed by grep.
- `functions/package.json` — added a no-op `"build"` script (the old `tsc` step is gone along with
  `tsconfig.json`, but `firebase.json`'s `predeploy` hook still calls `npm run build`).
- `CLAUDE.md` — Cloud Functions command block updated to drop the `tsc` framing.
- Deleted `functions/src/*.ts`/`tsconfig.json` left deleted, not restored — no git operations performed
  (add/rm/commit stay the user's call).

**Verification:** `cd functions && npm run build && npm test` — build no-ops cleanly, all 218
pre-existing tests still pass unchanged (nothing besides the two string edits was touched).

**Next step:** Phase 3 (billing/subscriptions) proceeds on top of this backend, self-contained enough
to not depend on the deferred order/catalog multi-tenant threading — see the Phase 3 entry that follows
once that work lands this same session.

---

## 2026-09-12 — Marketing landing page; seller-shell store-resolution guard

**Status:** implemented and verified this session (`flutter analyze` clean — 4 pre-existing `info`
lints, `flutter test` 8/8 passing).

Picking up from the 2026-09-11 entries below. Two things landed:

1. **Public marketing page** (commit `3318770`, earlier today, undocumented until now): a new
   `lib/modules/marketing/` (`MarketingView`/`MarketingController`, route `/marketing`) is Sellora's
   own landing page — hero, how-it-works, pricing pulled from `SubscriptionPlanModel`, FAQ, footer.
   `AuthController.checkSession` now sends a signed-out visitor here instead of straight to
   `Routes.roleSelect`; `RoleSelectView` gained a "Learn more about Sellora" link back to it. Self-
   contained — no repository or model changes.
2. **Seller-shell store-resolution guard** (this session): closes the PHASE 2 item both this file and
   `SELLORA_IMPLEMENTATION_PLAN.md` had listed as open — "nothing blocks navigation while the store is
   resolving or missing." `SellerShellView` now reads `StoreScope.isResolving`/`current`/`errorMessage`
   (already-reactive state `SellerShellController.onInit()` was populating but nothing consumed) before
   rendering the tab shell: a loading state while resolving, an `EmptyState` with a "Try again" action
   (`SellerShellController.resolveStore()`, the same lookup `onInit` already ran, now re-callable) and
   a "Sign out" fallback (`SellerShellController.signOut()`, new) if it comes back empty. Deliberately
   does **not** add a store-creation screen — every current signup path already creates a store
   (2026-09-11 fix), so an empty `StoreScope.current` is a defensive/edge case, not a known-reachable
   one; building a creation flow for it now would be speculative scope, not this item.

**Changed:** `lib/modules/seller/shell/seller_shell_controller.dart` (extracted `onInit`'s lookup into
public `resolveStore()`, added `signOut()`), `lib/modules/seller/shell/seller_shell_view.dart` (the
guard), `SELLORA_IMPLEMENTATION_PLAN.md` (PHASE 2 section updated to match both changes above).

**Not done:** the store switcher and store-creation-recovery-screen items noted above remain open,
same as before.

**Verification gap, disclosed:** same as every prior entry in this file — no browser/widget-level
check of the new loading/error branches, only `flutter analyze` and the pre-existing
`seller_shell_controller_test.dart` cases (which still pass unchanged, since `onInit`'s behavior is
unchanged, just renamed-and-exposed). `signOut()` isn't unit tested — it's a thin wrapper around
`AuthRepository.signOut()` + `Get.offAllNamed`, matching `AuthController.signOut()`'s existing
(likewise untested) shape; testing GetX navigation here would need a full `GetMaterialApp` harness this
repo doesn't otherwise use for controller tests.

**Next step:** decisions #1/#4/#5 are still the gate for going further into PHASE 3+ (see 2026-09-11
entry below) — nothing in today's work changes that.

---

## 2026-09-11 — Multi-tenant pivot: Phase 0 audit, Phase 1 foundation, Phase 2 started

**Status:** in progress, uncommitted. Supersedes the "no implementation code written" status on every
entry below — implementation began without a separate explicit sign-off message, on the reasoning
that decisions #2 (Firestore subcollection model) and #3 (path routing at `/s/:slug`) from the
2026-09-08 design doc are the only two Phase 1–3 depend on, both already recommendations rather than
open questions, and phases 1–3 don't touch Q2/Q3 (CJ account ownership, IntaSend split capability) per
that entry's own note. Decisions #1, #4, #5 (buyer account scoping, multi-store-per-seller, white-label
depth) are still open and should be confirmed before Phase 3 (seller onboarding/entitlements) goes far.

**Changed on disk:**
- `SELLORA_ARCHITECTURE.md`, `SELLORA_IMPLEMENTATION_PLAN.md` — audit + 8-phase plan (finer-grained
  than the design doc's phase list, adapted to what actually exists in the repo).
- Phase 1: Sellora theme pair (`#FFC107` / `#303F9F`) with system dark mode in `app_theme.dart`,
  shared `lib/core/widgets/app_page.dart` (page header, search field, loading/error states), seller
  dashboard migrated to the shared header.
- Phase 2 (partial): `lib/modules/storefront/` — `StoreScope` (`GetxService` resolving `/s/:slug` to
  a `StoreModel`, tested in `test/store_scope_test.dart`), `StorefrontView`/`Controller`/`Binding`
  wired into `app_pages.dart`/`app_routes.dart`/`initial_binding.dart`. `ProductRepository` gained
  `storeProducts(storeId, ...)` (mock + Firebase implementations). `FirestoreService` gained
  `storeProducts()`/`storeOrders()` subcollection accessors.
- `firestore.rules` — added `stores/{storeId}/products` and `stores/{storeId}/orders` subcollection
  rules. These paths existed in `firestore_service.dart` with no matching rule, which under
  Firestore's default-deny meant they were unreachable — a latent bug, not a leak, but it would have
  silently broken the first real-Firestore run.
- `OrderRepository` gained `storeOrders(storeId)` (mock + Firebase), mirroring `storeProducts()`. Like
  `storeProducts()`, this reads the new subcollection only — `placeOrder` still writes to the flat
  `orders` collection, so `storeOrders()` returns nothing against real Firestore until that write path
  migrates. Mock's version filters the existing seed list by `OrderModel.storeId` instead, since mock
  orders already carry that field.
- `firebase.json` gained an `emulators.firestore` block (port 8080, UI disabled) so `firebase
  emulators:exec` runs non-interactively.
- New `firestore-tests/` — a small Node package (`@firebase/rules-unit-testing`, run via
  `npm test`, which shells out to `firebase emulators:exec --only firestore "node --test"`) with
  `tenant-isolation.test.js`: 5 tests proving a seller can write/read/update only their own store's
  `products`/`orders`, a buyer's `customers` profile is private to them + their store's seller + admins,
  and the storefront stays publicly readable for guests. All 5 pass against the real emulator, with
  the rules engine's own `PERMISSION_DENIED` responses visible in the log — not vacuous passes.

**Verification:** `flutter analyze` clean (only 6 pre-existing `info`-level lints), `flutter test`
passes (2 tests), `npm test` in `firestore-tests/` passes (5 tests, ~12s against the emulator).

**Found and left alone:** `functions/node_modules` (5,839 files) is already committed to git. Not this
session's doing and not touched — flagging it here since it's the kind of thing a later session might
otherwise "fix" by surprise. `firestore-tests/node_modules` is gitignored so this isn't repeated.

**Not done:** route middleware enforcing store scope on seller-admin routes (only the public storefront
resolves a slug today), store-scoped `customers`/`settings`/`collections` repository *methods* (the
Firestore path and rules exist; nothing in `lib/` reads/writes store-scoped customers yet beyond
`AuthRepository`'s existing write), the `placeOrder`/product-create write-path migration to the new
subcollections, and any indexes for `storeOrders()`/`storeProducts()` (none needed yet — both do a bare
`.get()`/`.orderBy()` with no `.where()`).

**Also added this session:** `StoreScope.resolveForSeller(sellerId)` (refactored `resolveSlug` and it
onto a shared `_resolve` helper to avoid duplicating the loading/error-state bookkeeping), wired into
`SellerShellController.onInit()` so every seller-admin route populates `StoreScope.current` with the
signed-in seller's own store, the same way the public storefront does for a slug. Picks
`storesForSeller(sellerId).first` — a placeholder for "the active store" until a store switcher exists
(decision #4). Both `SellerShellController` and `StoreScope` take constructor-injected dependencies
(default to `Get.find`) so this is unit-testable without a GetX test harness; see
`test/seller_shell_controller_test.dart` and the two new cases in `test/store_scope_test.dart`.

**Gap found, not fixed:** `AuthRepository.signUpSeller` (both mock and Firebase) never calls
`StoreRepository.createStore` — a freshly-registered seller has no `StoreModel` at all, ever. Today
nothing reads `StoreScope` from the dashboard so this was invisible; `resolveForSeller` now surfaces it
correctly as "no store yet" rather than crashing, but there is still no screen that lets a seller
create one. This is Phase 3 work ("seller onboarding/entitlements... store creation"), not fixed here.
The mock quick-login path (`mock-seller` / `mock-seller-2`) is unaffected — those uids already have
seeded stores.

**Verification gap, disclosed:** did not drive this through an actual browser. This environment has
neither `chromium-cli` nor Python (the two paths the `run` skill's browser-driven pattern needs), and
Flutter web renders to canvas rather than DOM text nodes, so generic Playwright text-selectors aren't
reliable without first enabling Flutter's semantics/accessibility tree — a setup investment outside
this change's scope. Relied instead on `flutter analyze` (clean) and unit tests exercising the exact
`onInit()` path for both a signed-in and a signed-out seller. Worth a `/run-skill-generator` pass if
browser-driven verification becomes routinely needed for this repo.

**Next step:** decisions #1/#4/#5 are still open and Phase 3 (seller onboarding/entitlements) depends
on #4 (single vs. multi-store per seller changes the dashboard's store-picker and the custom-claim
shape) — worth confirming before going much further into Phase 3. Within Phase 2 itself, still open:
route middleware/guard for seller-admin routes (today `SellerShellController` resolves the store but
nothing blocks navigation while it's resolving or missing), and the `placeOrder`/product-create
write-path migration onto the `stores/{storeId}/...` subcollections.

---

## 2026-09-11 — TODOD.md adopted as phase framework; security/checkout hardening

**Status:** implemented and verified this session (`flutter analyze` clean, `flutter test` — 8/8
passing, `cd functions && npm run build` clean).

The user handed in `TODOD.md`, a 56-section "master build prompt" asking for a full Shopify-class
rebuild in one pass, plus an instruction to "remove all mock data." Neither is something to execute
literally in one session — `TODOD.md`'s own rules say to work in phases and audit first, and this
repo's `SELLORA_ARCHITECTURE.md` already shows the real backend isn't close to safe to point real
money at. Three decisions were confirmed with the user before writing any code:

1. **Phase framework**: adopt `TODOD.md`'s `PHASE 0`–`PHASE 12` numbering going forward (re-keyed into
   `SELLORA_IMPLEMENTATION_PLAN.md`), rather than restarting the project under it — the existing audit
   and phased plan stay the source of truth for *what's actually next*, `TODOD.md` for *how phases are
   named/ordered*.
2. **Platform service fee: 2%** (`TODOD.md` §15), replacing the app's previously-unused 5%
   `defaultCommissionPercent` constant. Renamed to `AppConstants.platformServiceFeeRate = 0.02`.
3. **Tenant write-path migration deferred** — `stores/{storeId}/products`/`.../orders` stay read-only
   this pass; new work continues against the flat `listings`/`orders` collections.

### What "remove mock data" actually required

A second, sharper audit pass (reading `functions/src/*` and the checkout/repository code directly,
not just the existing docs) found the real backend was further from usable than documented — flipping
`AppConstants.useMockData` to `false` as-is would have shipped a self-escalating-privilege,
unverified-payment app:

- `firestore.rules` let a user set their own `role` to `'admin'` — every privileged check in the
  ruleset is `role() == 'admin'`.
- `listings` writes checked `role() == 'seller'` only, not ownership — any seller could edit any other
  seller's listing.
- Checkout was fully client-trusted: `CheckoutController` computed `total` and wrote
  `paymentReference` itself; `FirebaseOrderRepository.placeOrder` just `.set()` it verbatim.
- `intasendWebhook` was a stub — logged the payload, verified nothing, never touched Firestore. No
  payment was ever actually confirmed anywhere.
- The old `onOrderCreated` trigger's CJ-fulfillment call POSTed to the auth-gated `cjCreateOrder`
  function with no `Authorization` header — it would 401 every time, and it also ran before payment was
  verified (its own comment already flagged this).
- `functions.config()` (CJ/IntaSend credentials) is deprecated in the installed `firebase-functions`
  version, with no `.env`/`.runtimeconfig.json` present — a fresh deploy would call CJ/IntaSend with
  `undefined` credentials.
- `AuthRepository.signUpSeller` (mock and Firebase) never created a `StoreModel` — confirmed still true
  from the 2026-09-11 Phase-2 entry above.

None of this needed new decisions or real provider credentials to fix correctly, so it got fixed this
session. `useMockData` stays `true` — flipping it for real use is a separate step gated on things only
the user can supply (a real CJ Dropshipping account, a confirmed IntaSend production setup with the
webhook verification scheme reconfirmed against current docs, and `firebase functions:secrets:set` run
with real values).

### Changed

- **`firestore.rules`**: `users.role` can no longer be self-written (only an existing admin can change
  someone's role); `users` read narrowed from "any signed-in user" to owner-or-admin; `listings`
  create/update now ownership-checked; `orders` create is `allow create: if false` (Cloud-Function-only
  via Admin SDK).
- **`functions/src/orders.ts`**: new `createOrder` (`onRequest`, `requireAuth`) re-prices every item
  from `listings` server-side, computes the 2% fee snapshot, writes the order with
  `paymentStatus: 'pending'`. The old `onOrderCreated` trigger and its broken CJ call are gone —
  fulfillment now happens from the webhook, after payment is confirmed, not at document-creation time.
- **`functions/src/cj.ts`**: extracted `placeCjOrder()` as a plain function so the webhook can call it
  in-process (no HTTP self-call, no missing-auth-header bug); migrated CJ credentials to
  `defineSecret`/`runWith`.
- **`functions/src/intasend.ts`**: `intasendWebhook` now verifies a shared "challenge" value (flagged
  inline as needing reconfirmation against IntaSend's current docs before go-live — same caveat style
  already used for `cj.ts`'s auth handshake) and, on a confirmed payment, looks the order up by
  `api_ref` (the order id), sets `paymentStatus`/`paymentReference`, and calls `placeCjOrder` per item.
  Migrated the secret key to `defineSecret`.
- **`lib/data/models/order_model.dart`**: added `OrderPaymentStatus` (`pending`/`paid`/`failed` —
  named distinctly from `IntasendService`'s own `PaymentStatus` to avoid an import collision) and the
  fee snapshot fields (`serviceFeeRate`, `serviceFeeAmount`, `sellerRevenue`, `paymentFee`); added
  `copyWith`.
- **`lib/modules/buyer/checkout/checkout_controller.dart`** +
  **`lib/data/repositories/firebase_order_repository.dart`**: checkout now creates the order
  server-side (via a new `ApiEndpoints.createOrder` call) *before* contacting IntaSend, using the
  server-assigned order id as the payment's `api_ref`/narrative, so the webhook can find it later.
  Mock mode is untouched — it still fakes an instant "paid" order in one step, since there's no server
  to re-price against or webhook to wait on.
- **`lib/data/repositories/auth_repository.dart`** + **`mock/mock_auth_repository.dart`**:
  `signUpSeller` now creates a `StoreModel` (slug derived from the store name via a new
  `lib/core/utils/slug.dart`, de-duplicated against existing slugs). Both repos now take an optional
  constructor-injected `StoreRepository` (default `Get.find`), matching the testability pattern the
  2026-09-11 Phase-2 entry above established for `SellerShellController`/`StoreScope`.
- **`lib/app/bindings/initial_binding.dart`**: `StoreRepository` registration moved before
  `AuthRepository` in both branches — required now that `AuthRepository`'s constructor resolves it
  eagerly via `Get.find`.
- **`SELLORA_ARCHITECTURE.md`** (section K) and **`SELLORA_IMPLEMENTATION_PLAN.md`** (re-keyed to
  `TODOD.md`'s phase numbering) updated to match.
- New `test/auth_repository_test.dart` (2 cases: store gets created on signup; slug de-duplication).

### Not done this session (deliberately)

Everything in `TODOD.md` PHASE 3–7/9–11 (billing UI, CJ catalog import, store builder, storefront,
analytics/marketing, admin panel, i18n); the `stores/{storeId}/...` write-path migration; the payment
custody model decision (the two conflicting 2026-09-08 entries above are still unresolved — this
session's webhook/order work is written to be compatible with either outcome); the CJ shared-vs-
per-seller account decision; subscription-payment webhook wiring (`billing_history` writes are still
client-side and silently blocked by rules against real Firestore — same class of bug as the order one
just fixed, next in line for Phase 3).

### Verification gap, disclosed

Did not drive the new `createOrder`/webhook flow through the Firebase emulator or a real IntaSend
sandbox call — this environment has neither running, and the IntaSend webhook "challenge" scheme is
implemented from memory of their published docs, not verified against a live account. Flagged inline
in `intasend.ts` and in `SELLORA_IMPLEMENTATION_PLAN.md`'s PHASE 12 as needing a firestore-tests case
and a real-account read-through before deploy, rather than claimed as tested.

---

## 2026-09-09 — Payment design finalized: IntaSend Split Payments mechanics

**Status:** design complete, still awaiting overall sign-off. No implementation code written.

Section 04 fully specified per explicit direction: buyer funds collect into Sellora's IntaSend
account and split automatically at collection via IntaSend Split Payments (sub-accounts) — seller's
net share to their own sub-account, CJ-cost-plus-fee stays with Sellora. Design document updated in
place: <https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f>

New content:
- **Split calculation** — computed fresh per order (not a stored ratio), since product mix varies:
  `orderTotal / costOfGoods / platformFee / sellerNet`, in minor units, rounding remainder to
  Sellora never the seller.
- **Paying CJ** — explicit that CJ isn't an IntaSend party, so this is a second, Sellora-initiated
  payment funded from its own settled balance, not a live per-order transfer. Sellora keeps a small
  bounded float in its CJ wallet so fulfilment doesn't wait on settlement timing — a materially
  smaller exposure than the original direct-to-seller design's open "who fronts CJ" problem.
- **Payout hold policy** — recommended holding seller payouts until delivery is confirmed (standard
  marketplace practice). Flagged a real gap in the current codebase: `OrderStatus.delivered` is
  seller-self-reported with nothing independent behind it, which is a conflict of interest as a
  payout trigger — recommended wiring the hold timer to CJ's own tracking data
  (`cjTrackShipment`, already stubbed) instead of trusting self-report alone.
- Data model: `orders/{id}` gains a `settlement` map; new `stores/{id}/payouts` subcollection; new
  isolation tests for both. `stores/{id}/private/payments` gains `intasendSubAccountId`/`kycStatus`.
- Commission model reverts back to "live split at collection" (from the prior revision's "invoiced
  arrears," which was specific to the direct-to-seller design this supersedes).
- Sharpened the open question that used to be "does IntaSend support this" (now decided) into five
  concrete API specifics to confirm before Phase 4: split precision (fixed amount vs. percentage),
  sub-account KYC turnaround, Payouts API minimums/fees, settlement schedule, and refund behavior on
  an already-split transaction.

**Next step:** unchanged from the prior entry — Phase 0 sign-off, then Q1–Q5 (Q3 now the five-item
IntaSend checklist above).

---

## 2026-09-08 — Bug fixes + responsiveness pass (current marketplace UI)

**Status:** done. First real code changes in this repo (everything above was design-only). Scoped
to the existing marketplace-model Flutter UI — unrelated to the multi-tenant pivot below, which is
still awaiting sign-off and untouched by this pass.

### Bugs fixed

- **Buyer shell tab restore ran on every `build()`**, not once — `Get.arguments['tab']` was
  re-applied via `addPostFrameCallback` on any rebuild, silently snapping the user back to the
  checkout-handoff tab (e.g. after a MediaQuery-driven rebuild on resize). Moved into
  `BuyerShellController.onInit()`, which runs exactly once per controller lifetime.
- **Data loss on rebuild**: `TextEditingController`/`GlobalKey<FormState>` were created inline in
  `StatelessWidget.build()` in `LoginView`, `RegisterBuyerView`, `RegisterSellerView`,
  `CheckoutView`, and onboarding's `_PaymentStep` — any rebuild (a responsive `MediaQuery` read is
  exactly that trigger) would silently wipe whatever the user had typed. Converted all five to
  `StatefulWidget`s owning their controllers in `initState`/`dispose`. This was a prerequisite for
  adding responsiveness to those screens safely, not just a cleanup.
- **`MyListingsView`'s relist switch was a no-op**: `Switch.onChanged` unconditionally called
  `unlist`, so turning a paused listing back on silently did nothing. Added
  `MyListingsController.relist()` and branched on the switch's new value.
- **Admin catalog sync's "Last synced" label never updated**: the controller exposed the repo's
  plain `DateTime?` getter through an `Obx`, which has no reactive dependency on a non-Rx read — the
  sync worked, the label just never refreshed. Made `lastSyncedAt` an `Rxn<DateTime>` on the
  controller.
- **Mock-mode cold start stalled ~3s on every launch**: `MockAuthRepository.userChanges` never
  emitted until an explicit sign-in/out, so `checkSession()`'s `.first` always hit its timeout —
  directly undercutting the README's "try it in 60 seconds" claim. Now yields the current value
  immediately, matching how the Firebase-backed implementation behaves.
- **`RoleSelectView` could overflow** on a short viewport: a `Spacer()`-based `Column` with no
  scroll fallback. Fixed with a scroll view and fixed spacing rather than a flex spacer — note a
  `Spacer()` inside a `SingleChildScrollView` is a different, worse bug (unbounded-height
  `RenderFlex` crash), so the fix is spacing, not just "add scrolling."
- Plus the 5 pre-existing `flutter analyze` lint infos (missing `const`, double-quote style).

### Responsiveness

- New `lib/core/utils/responsive.dart` — breakpoints, `BuildContext` extensions (`isWide`,
  `pageHorizontalPadding`, …), `ResponsiveCenter` (caps + centers page content on wide screens),
  `centeredSliverPadding()` for `CustomScrollView` screens, `productGridDelegate()`
  (`SliverGridDelegateWithMaxCrossAxisExtent`-based, so grids grow columns with width instead of a
  hardcoded count).
- New `lib/core/widgets/adaptive_shell_scaffold.dart` — bottom nav bar below desktop width, a
  Material `NavigationRail` at/above it. All three portal shells (buyer/seller/admin) now use it,
  which also collapsed three near-duplicate shell implementations into one.
- Buyer product grid and both stat-card dashboards (seller, admin) moved from a fixed
  `crossAxisCount` to extent-based grids.
- Every list/form screen wrapped in `ResponsiveCenter` so content stops stretching edge-to-edge on
  desktop web; auth/checkout/onboarding forms capped at 440–560px and centered.
- `BottomActionBar` and the two bottom-sheet forms (seller catalog listing, subscription switch) cap
  and center their content — deliberately via a `Row`, not `Center`/`Align`: those slots (Scaffold's
  `bottomNavigationBar`, a modal bottom sheet) give bounded-but-loose height, which `Align` fills
  entirely per its own documented sizing rule; a `Row`'s cross axis always hugs its child regardless.
- `ManifestStub` and `EmptyState` got overflow/width guards so they hold up at both very narrow and
  very wide sizes.

### Verification

`flutter analyze` — 0 issues (was 5 infos). `flutter build web --release` — succeeds.

### Changed

23 view/controller files, plus 2 new files (`responsive.dart`, `adaptive_shell_scaffold.dart`) and
`common.dart`/`empty_state.dart`/`manifest_stub.dart`. Nothing under `functions/`, routing, or
Firestore rules touched — out of scope for this pass and overlapping with the pivot work below.

---

## 2026-09-08 — Payment model revision: platform collect-and-disburse

**Status:** revises decision #4 below. **No implementation code written.**

The user explicitly overrode the direct-to-seller recommendation: buyer funds must land at Sellora
first, Sellora pays CJ, keeps a service fee, and disburses the remainder to the seller. Section 04 of
the design document was rewritten to the safe version of that model rather than re-arguing against it.

**New recommendation:** collect through a licensed processor's marketplace/split-payment rails (the
IntaSend/Flutterwave/Paystack pattern behind Jumia, Uber, Airbnb, Stripe Connect) — never a bank or
M-Pesa account Sellora itself controls. The processor stays custodian of funds in transit; Sellora
only instructs the split (CJ cost / platform fee / seller payout) via API. This is lower-risk than
Sellora pooling funds itself, but not risk-free: Sellora is very likely still merchant of record for
refunds/disputes, and the processor will likely require its own aggregator/KYB onboarding.

**A genuine upside surfaced by this change:** the earlier "who fronts CJ" risk (`functions/src/cj.ts`
uses one shared platform CJ credential) is resolved differently now — Sellora holds the buyer's
payment before it owes CJ anything, so a shared CJ account is no longer credit extended to sellers,
just ordinary treasury/reconciliation work. Q2 below was downgraded accordingly.

**Commission model reverses again:** now a live split at settlement (natural, since Sellora holds the
funds) rather than the invoiced-arrears approach the direct-to-seller version required.

**New blocking question, sharper than before (Q3):** does IntaSend actually support marketplace/split
payments with sub-merchant custody? `functions/src/intasend.ts` has no notion of sub-merchants today.
If not, Flutterwave's Multi-Split Payments or Paystack's Split Payments are the named fallbacks — both
operate in Kenya and are built for exactly this.

**Changed in this repo:** the design artifact (`https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f`),
Section 04 and the open-questions Q2/Q3, updated in place. This worklog entry.

**Next step:** unchanged — still gated on Phase 0 sign-off. Q3 (processor capability) is now the
sharper blocker for Phase 4 specifically.

---

## 2026-09-08 — Multi-tenant storefront platform: design

**Status:** design complete, awaiting sign-off. **No implementation code written.**

### Goal

Evolve Sellora from a single shared marketplace into a Shopify-style platform. Each seller gets a
customizable storefront; buyers sign up as customers of *that specific store* rather than as global
Sellora accounts. Sellora keeps the seller dashboard, the shared CJ catalog, and subscription
billing. The marketplace-style shared buyer app is retired.

### Deliverable

Full design document (5 sections + open questions):
<https://claude.ai/code/artifact/0b1113cb-1fc9-4176-9dc7-7df3bfda170f>

It covers account scoping options, the Firestore model and security rules, Flutter Web routing,
payment flow of funds, and a phased migration plan. The summary below is the decision record; the
document holds the reasoning, the comparison tables, and the isolation test checklist.

### Decisions to confirm

| # | Question | Recommendation |
|---|---|---|
| 1 | Buyer account scoping | One Firebase Auth pool + a `stores/{storeId}/customers/{uid}` profile document. **Not** Cloud Identity Platform multi-tenancy — GCIP charges per MAU from the first customer and adds tenant provisioning to the seller signup path, to buy credential isolation when MVP only needs data isolation. Accepted cost: global email uniqueness. |
| 2 | Firestore model | Store-owned data moves under `stores/{storeId}/…` **subcollections**, not flat collections with a `storeId` field — so a missed `.where()` cannot leak across tenants. Admin cross-store views become collection group queries. |
| 3 | Routing | Path routing at `/s/:slug/…` behind an injected `StoreScope`, so subdomains later are a resolver swap. Firebase Hosting cannot do wildcard subdomains — that, not effort, is why paths win for the MVP. |
| 4 | Payments | Each seller connects **their own** IntaSend account; buyer funds never touch Sellora. Sellora's revenue stays the subscription. Platform-collect-and-disburse would make Sellora a payment aggregator (CBK/NPS Act licensing, plus likely a breach of IntaSend's own terms). |
| 5 | Migration | GetX View→Controller→Repository, the `useMockData` dual-implementation split, and Meridian all survive. The buyer portal, `storefrontFeed()`, `UserRole.buyer`, and the global cart singleton do not. |

### Findings from reading the codebase

Three things surfaced during the review that are worth carrying forward regardless of the pivot:

- **`functions/src/cj.ts` uses one platform-level CJ account.** If checkout money goes directly to
  sellers, who pays CJ for the goods? A shared CJ account means Sellora fronts every merchant's
  inventory cost and invoices afterwards — unsecured credit to small sellers, a materially different
  business. Per-seller CJ accounts keep Sellora as pure software. Demo mode hides this entirely.
- **`CheckoutController` prices the cart client-side** and writes an order carrying a client-set
  `total` and `paymentReference`. Already a hole; with real merchant money behind it, it is the whole
  problem. Order creation must move into a Cloud Function that re-prices from listings.
- **`firestore.rules` allows `users` read to any signed-in user.** Today that exposes every user
  document; once buyers are tenants it would be a platform-wide customer list readable by any seller.

### Changed in this repo

- `CLAUDE.md` — new. Architecture orientation for future sessions.
- `WORKLOG.md` — new. This file.

Nothing under `lib/`, `functions/`, or `firestore.rules` was touched.

### Blocked on

1. Is there any live production data? Everything in the repo reads as pre-launch
   (`useMockData = true`, `baseFunctionsUrl` still `YOUR_FIREBASE_PROJECT`,
   `Firebase.initializeApp()` commented out). Confirming this lets the migration skip a backfill.
2. Does each seller bring their own CJ Dropshipping account, or does Sellora hold one shared account?
   Gates the payments phase and determines whether Sellora is extending credit.
3. Has IntaSend confirmed a platform/connect capability for marketplaces? Determines whether sellers
   supply raw API keys (stored in Secret Manager, never Firestore) or Sellora receives scoped
   per-merchant credentials. Ask explicitly whether funds ever transit a Sellora-owned wallet — if
   they do, the custody problem returns.
4. Will one seller ever need more than one store? Cheap now, expensive to retrofit — it changes the
   custom-claim shape and the dashboard navigation.
5. How white-label must this be at launch? If merchants need password-reset emails and sign-in pages
   carrying *their* brand, that is the trigger for Identity Platform, and it belongs in phase 1
   rather than a later migration.

### Next step

Sign off on the five decisions, answer Q1–Q5 above, then start phase 1 — `StoreModel`, `StoreScope`,
slug resolution, path URL strategy, and the `/s/:slug` route tree, all against mock data with two
seeded demo stores. Phases 1–3 need no answers to Q2 or Q3; only the payments phase is gated.
