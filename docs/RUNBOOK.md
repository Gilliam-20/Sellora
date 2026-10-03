# Sellora runbook

How to ship, check, roll back and investigate Sellora in production. First-time project setup
(dashboard settings, secrets, admin account) is the owner checklist in `TODO.md`; this file is for
running the system after that.

Three things deploy separately, and their order matters:

| Piece | Lives in | Deployed with |
|---|---|---|
| Database (schema, RLS, triggers, cron jobs) | `supabase/migrations/` | `cd supabase && npx supabase db push` |
| Backend (`api` Edge Function) | `supabase/functions/` | `cd supabase && npm run deploy` |
| Web app | `lib/` | `flutter build web` then `firebase deploy --only hosting` |

## 1. Releasing

1. **Test locally.** From the repo root, run `flutter analyze` and `flutter test`. The one known
   failure is in `seller_shell_controller_test`. Then run `cd supabase && npm test` and
   `npm run check:functions`. Don't ship on any other failure.
2. **Migrations first.** Run `cd supabase && npx supabase db push`. Migrations only ever add: new
   columns have defaults, and new functions and views replace old ones in place. So the
   currently deployed function and web app keep working against the new schema. A new migration
   must keep that property. If it can't, split it into an additive release and a later cleanup
   release.
3. **Then the function.** Run `npm run deploy`. A function that reads a new column must ship after
   the migration that adds it. For example, `createOrder` reads `stores.is_suspended`
   (`20261003000200_admin_platform.sql`). Deploying it before that migration would make every
   checkout fail.
4. **Then the web app.** Run
   `flutter build web --dart-define=SELLORA_RELEASE=$(git rev-parse --short HEAD)`, then
   `firebase deploy --only hosting`. `SELLORA_RELEASE` tags error reports with the build they came
   from (Admin → Activity → App errors).
5. **Verify.** Run
   `cd supabase && SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/preflight.js`.
   It checks applied migrations, Vault secrets, cron jobs and their failures over the last 24h,
   plans, the admin account and `/health`, and names the fix for each failure. Then open one
   storefront and the admin Overview in a browser.

If a release note in `TODO.md` says two steps must ship together, do them back to back. For
example, the function and web app both changed the shipping-address shape on 2026-10-03.

## 2. Rolling back

- **Web app.** In Firebase console → Hosting → release history, roll back to the previous
  release. Or check out the previous commit and repeat release step 4.
- **Function.** Check out the last good commit and run `npm run deploy`. The function is stateless,
  so redeploying is the whole rollback.
- **Database.** Migrations aren't reversed. Write a new migration that undoes the change, test it
  in `supabase/tests/rls.test.mjs`, and push it. Before running anything destructive by hand in
  the SQL editor, take a backup (§4).
- **Order matters in reverse too.** Roll back the web app and the function before any migration
  they depend on.

## 3. Secrets

The function's secrets are `CJ_API_KEY`, `INTASEND_SECRET_KEY`, `CRON_SECRET`, plus the optional
`INTASEND_WEBHOOK_CHALLENGE`, `ALLOWED_REDIRECT_ORIGINS` and `SELLORA_DEBUG_LOGS`. Set them with
`npx supabase secrets set NAME=value` and list the names with `npx supabase secrets list`. Never
paste a value into a ticket, a commit or chat.

To rotate one:
1. Issue the new key with the provider.
2. Run `secrets set` with the new value. Secrets apply to new function invocations; redeploy with
   `npm run deploy` if a request still uses the old one.
3. Revoke the old key with the provider.

`CRON_SECRET` also lives in Vault as `sellora_cron_secret`, which the pg_cron jobs send. Update
both, Vault first, or the scheduled jobs get 401s until they match. Check with preflight
(`cronFailures24h`).

## 4. Backups and staging

- **Backups.** Supabase dashboard → Database → Backups shows what the plan keeps. Point-in-time
  recovery is a paid add-on, and turning it on is an owner decision
  (`SELLORA_IMPLEMENTATION_PLAN.md` PHASE 12). Until it's on, take a manual dump before any risky
  change: `npx supabase db dump -f backup-$(date +%F).sql`, plus `--data-only` for a data copy.
  Keep dumps out of git: they contain customer data.
- **Staging.** Use a second Supabase project. Link it with
  `npx supabase link --project-ref <staging-ref>`, run `db push`, `npm run deploy` and
  `secrets set` with sandbox CJ/IntaSend keys, then build the app with
  `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...` for staging. Re-link
  to production afterwards. `supabase link` is per-directory state, so check which project you're
  linked to before every `db push`.

## 5. When something breaks

| Symptom | Look at | Usual fix |
|---|---|---|
| Checkout fails for everyone | Dashboard → Edge Functions → `api` → Logs (`createOrder`); preflight | A migration the function needs isn't applied (release step 2), or a CJ/IntaSend secret is wrong |
| Checkout refused for one store | The seller in Admin → Sellers (standing, subscription); the store in Admin → Stores (suspension) | `seller_order_gate` refused it (lapsed, suspended, order limit), or the store is suspended |
| "This store doesn't ship to that country" | The store's shipping zones (Customize store) | The seller enables the zone. `createOrder` enforces it server-side |
| Paid orders not reaching CJ | Admin → Orders (CJ status); function logs for `fulfillOrder` | `sellora-retry-fulfilments` retries every 30 min. Orders parked as `NEEDS_RECONCILIATION` need a human |
| Scheduled jobs not running | preflight (`cronJobs`, `cronFailures24h`) | Vault `sellora_api_url`/`sellora_cron_secret` don't match the function (§3) |
| Errors in buyers' browsers | Admin → Activity → App errors (grouped by message, 30 days kept) | The `release` in the report's context says which build |
| Who changed a store, plan or order | Admin → Activity → Audit log | Append-only: rows can't be edited or removed |

**Take a store offline:** Admin → Stores → the store → Suspend store, with a reason the seller will
see. Its catalog disappears and checkout refuses it. The seller's account and billing are untouched.
To stop a seller everywhere, suspend the seller in Admin → Sellers instead.

**Refund:** Admin → Orders → the order → Refund. IntaSend settles in KES, so the amount is in KES.
