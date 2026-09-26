# Sellora Security & Architecture Audit — Supabase edition

Audit date: 26 September 2026. This replaces the Firebase-era `SELLORA_ARCHITECTURE.md` (11 September)
as the current audit. It covers the repository as found after the Supabase migration commits
(`bfa8f8f`, `e307b3d`). Nothing here has been run against the real Supabase project, CJ, or IntaSend.
The same was true of the migration itself (see `WORKLOG.md`, 2026-09-26/27).

Baseline at audit time: `cd supabase && npm test` passes (the RLS/PGlite suite, the grant-admin
tests, and 63 Deno tests with 261 steps).

---

## 1. Current architecture, as built

```text
Flutter (GetX)                         Supabase
─────────────────                      ─────────────────────────────────────────────
View → Controller → Repository ──────► PostgREST + RLS  (profiles, stores, products,
          │                             │                orders*, notifications, plans…)
          │                             └─ triggers: handle_new_user, *_guard_update
          └─ DioClient (+JWT) ────────► Edge Function `api` (verify_jwt off; per-route
                                         verifyAuth → Supabase Auth)
                                           ├─ CJ Dropshipping  (one platform credential)
                                           ├─ IntaSend         (one platform credential)
                                           └─ service role → SQL functions
                                              (activate_subscription,
                                               attach_order_payment_attempt,
                                               consume_rate_limit)
pg_cron → pg_net → /cron/<job> (x-cron-secret from Vault)
Storage: `store-media` (public read, owner-folder write)
```

\* `orders` has a column-level grant: clients cannot `select *` and may update only `status`.

### What is already sound. Keep it.

| Area | What exists | Verdict |
|---|---|---|
| Price authority | `createOrder` takes only `{pid, vid, quantity}`, re-reads the seller's `sell_price`, CJ's live supplier cost, and CJ's freight quote. It derives currency from the shipping country and refuses a non-positive total. | Correct. Matches brief §7. |
| Payment confirmation | The client never marks anything paid. Both the webhook and the poll re-verify with IntaSend, bind the invoice to the order (`paymentRefMatches`), and check the amount. | Correct in design (§8/§9), but see finding H3. |
| Idempotency | CJ push is a compare-and-set claim on `(cj_order_status, cj_push_attempts)`. Subscription activation is guarded on `status='pending'` in one SQL transaction. Refund claims use CAS. | Correct. |
| Admin identity | `app_metadata.role`, set only by the service role (`grant-admin.js`), read by both RLS (`is_admin()`) and the function. No email checks. | Correct (§6/§16). |
| Sign-up | Profile, store and customer rows are created by a `security definer` trigger that accepts only legitimate buyer/seller metadata. The client cannot mint roles. | Correct. |
| Secrets | No secret in tracked files or git history. `functions/.env` and `supabase/functions/.env` are gitignored. The app holds only the URL and publishable key. | Correct (§13/§14). |
| Server-only SQL functions | `revoke execute … from public, anon, authenticated` on every privileged function. | Correct (§26). |
| External calls | Fetch timeouts (15 s CJ, 20 s IntaSend). Internal errors are logged and callers get a generic 500 (`publicError`). JSON-line logs with named alerts. | Adequate (§30/§33). |
| XSS | No HTML/webview renderer in the app. All seller/CJ text renders through Flutter `Text`. Storage rejects SVG. | Low risk (§27). |
| Firebase remnants | None in `lib/`, `pubspec.yaml`, or Android. What remains: `functions/` (retired, an owner deletion step), `firestore-tests/`, and `firebase.json` hosting (still needed). | Clean (§38). |

The brief's target architecture (Flutter → repositories → Edge Functions → providers, with RLS as
the database boundary) is **already the architecture**. The work left is closing specific gaps, not
a restructure. Moving `lib/modules` to `lib/features`, or splitting the schema into the brief's ~40
tables, would add risk without closing any hole, so this audit does not recommend either.

---

## 2. Findings

Severity is the damage a real attacker or a real bug could do **once money flows**.

### Critical / High

**H1. Seller revenue ignores the goods cost Sellora pays CJ.**
`splitServiceFee` sets `sellerRevenue = retailSubtotal − fee`. Under the chosen collect-and-disburse
model (WORKLOG 2026-09-08), Sellora pays CJ the supplier cost and freight out of the buyer's money.
The seller is therefore owed `retail − supplier cost − fee`, not `retail − fee`. As written,
`estimated_profit_usd` is negative by about the supplier cost on every order. The seller dashboard's
"net revenue" (`seller_dashboard_controller.dart:191`) overstates earnings by the same amount. No
payout is wired yet, so no money has moved. The first payout built on this column would overpay.
*Fix:* compute `seller_revenue_usd = retail_subtotal − supplier_subtotal − fee` server-side. Decide
who absorbs the freight margin.

**H2. A seller can price below cost, and Sellora eats the difference.**
Sellers write `products.sell_price` directly, and nothing requires it to cover CJ's cost. `createOrder`
refuses only prices ≤ 0. A $1 listing of a $20 item is a $19 loss per order to Sellora (see H1).
*Fix:* in `createOrder`, refuse any line whose `retailUnitPriceUsd` is below `supplierUnitPriceUsd`.
Add a `CHECK (sell_price >= 0)` in the DB, plus a floor warning in the import UI.

**H3. A suspended seller reactivates themselves by paying.**
`activate_subscription` unconditionally sets `profiles.seller_status = 'active'`, and it reaches that
from `subscribeSeller` → pay → confirm, which the seller drives. An admin suspension lasts until the
seller's next payment.
*Fix:* only promote `pendingApproval → active`, never `suspended → active`. `subscribeSeller` should
also refuse suspended sellers.

**H4. Any signed-in user, buyers included, can buy a seller subscription.**
`subscribeSeller` checks sign-in, not `role = 'seller'`. Activation then writes seller status and a
subscription onto a buyer profile.
*Fix:* require `profiles.role = 'seller'` in `subscribeSeller`, and assert it inside
`activate_subscription`.

**H5. Suspended or unsubscribed sellers keep selling.**
Suspension and subscription expiry are enforced only by `RoleMiddleware`, in the client. `createOrder`
checks that the store exists and the product is listed. It never checks the seller's `seller_status`
or `subscriptions.current_period_end`. RLS lets a lapsed seller keep inserting and listing products.
*Fix:* `createOrder` refuses unless the seller is `active` with an unexpired subscription. Add a
matching RLS condition (`seller_can_sell()`) on product insert, and on update-to-listed.

**H6. Plan limits exist only as display data.**
`listing_limit`, `order_limit` and `store_limit` are stored on plans, but nothing enforces them: not
RLS, not the function, not even the client. A seller can also create more stores through the
`stores` insert policy (the policy ignores `store_limit`).
*Fix:* a `BEFORE INSERT/UPDATE` trigger on `products` counting listed rows against the active plan.
Enforce `order_limit` in `createOrder`. Enforce `store_limit` in the stores insert policy. Brief §22.

**H7. Sellers can move order status in ways that contradict payment and fulfilment.**
The column grant limits sellers to `status`, but allows any value. A seller can mark an unpaid order
`shipped`/`delivered`, or `cancel` a paid one. A cancelled paid order still gets pushed to CJ
(`fulfillOrder` checks only for refunds), and the buyer is never refunded.
*Fix:* a transition trigger. Clients may only move `processing → shipped → delivered` on paid
orders. Cancelling a paid order goes through the admin refund path.

### Medium

**M1. The payment amount check fails open.** `verifyAmount` returns `ok` when it can't read an
amount from IntaSend's response. The webhook then fulfils "on the invoice binding alone". The invoice
amount is server-set, so exploitation needs a provider-side mismatch. Still, once the response shape
is confirmed against a real account, this must **fail closed**.

**M2. Public CJ endpoints have no rate limit.** `searchProducts`, `getProductDetail` and
`getCategories` are unauthenticated and limited only by a per-isolate in-memory cache. A script can
exhaust the single platform CJ quota and take browsing and checkout down for everyone. *Fix:* an
IP-keyed `consume_rate_limit` policy on the public routes. Better still, serve browsing from
`catalog_products` (already mirrored daily) and keep live CJ calls for import and checkout.

**M3. No audit trail for admin or financial actions.** Suspensions (`setSellerStatus` is a raw
profile update), plan edits, refunds and admin profile edits leave only function log lines, and none
at all for direct table writes. *Fix:* an append-only `audit_logs` table, written by triggers on
`profiles.seller_status`, `subscription_plans`, `stores` admin edits, and by the refund/payment paths.
No client insert, no update/delete for anyone. Brief §18/§19.

**M4. No immutable financial ledger.** Money figures live as mutable columns on `orders` and
`billing_history`. Refunds are appended to an `orders.refunds` jsonb. Reports would be rebuilt from
mutable rows. *Fix:* an insert-only `ledger_entries` table (`ORDER_PAYMENT`, `PLATFORM_FEE`,
`SUPPLIER_COST`, `SELLER_EARNING`, `REFUND`, `SUBSCRIPTION_PAYMENT`), written in the same SQL
transaction as the state change. This must come **before** payouts. Brief §24.

**M5. Webhook events aren't stored.** Replays are already harmless (re-verification plus CAS), but
there is no record for reconciliation or dispute handling. *Fix:* a `webhook_events` table with a
unique `(provider, invoice_id, state)`, written first. Brief §32.

**M6. Fee rate: partly resolved.** On 2026-09-26 the owner set the fee to a flat **7%**
(`SERVICE_FEE_RATE` in `orders.js`, with `AppConstants.platformServiceFeeRate` mirroring it for
display). TODO.md now agrees. Still open: `subscription_plans.commission_percent` (default 5) is
shown in the admin plans UI as "X% commission" but charged nowhere. Either drop it, or make
`createOrder` read it per plan.

**M7. Pending orders never expire.** An unpaid order keeps its FX rate and CJ cost snapshot
indefinitely and can be paid days later at stale prices. *Fix:* `expires_at` (for example 60 min).
Refuse payment after it, and mark the order `cancelled` with a pg_cron sweep.

**M8. Listed products expose the seller's cost and margin.** Listed `products` rows are public, and
`cost_price` rides along, so any buyer sees the seller's markup. *Fix:* a column-level grant for
`anon`/buyers, as `orders` already has. Also, `sold_count`/`rating` are seller-writable, so sellers can
fake social proof. Make them server-owned in `products_guard_update`.

**M9. No CJ stock check at checkout.** `products.stock` is seller-typed and unused. `createOrder`
doesn't check the variant's CJ inventory. An out-of-stock variant is charged, then fails the CJ push
and parks for a manual refund. *Fix:* check CJ variant stock inside `createOrder`. `getStock` already
exists, cached.

### Low

- **L1.** `storefrontFeed()`/`storeProducts()` fetch every listed row with no `.range()`. Paginate
  them (brief §34). `storefrontFeed` is also the retired shared-marketplace path.
- **L2.** There is no account-deletion flow, which Google Play requires for apps with sign-up.
- **L3.** Notifications between order counterparties take arbitrary text with no length cap. Add
  `CHECK (char_length(...) <= …)` and a cap on free-text profile/store fields in general.
- **L4.** `profiles.email` is copied at sign-up and never follows an Auth email change.
- **L5.** Supabase's default grants may still give `anon`/`authenticated` `TRUNCATE`/`TRIGGER` on
  public tables. PostgREST can't issue these, but revoking them is free defence in depth.
- **L6.** CORS is `*`. That's acceptable because auth is a bearer token, not a cookie. Note it and
  leave it.
- **L7.** Renewing early starts the new period at `now()`, so the seller loses the remaining days.
  This is a product bug, not a security one.

---

## 3. Source of truth (brief §40)

| Data | Source of truth | Notes |
|---|---|---|
| Identity / session | Supabase Auth | |
| Admin role | `auth.users.app_metadata.role` | Service-role only |
| Buyer/seller role | `profiles.role` | Written only by `handle_new_user`; guarded |
| Seller standing | `profiles.seller_status` + `subscriptions` | Enforced server-side (`seller_can_sell`, `seller_order_gate`) |
| Plan terms and limits | `subscription_plans` | Enforced server-side (H6, §6) |
| Retail price | `products.sell_price` (seller), validated by `createOrder` | Floor enforced at checkout (H2, §6) |
| Supplier cost / freight | CJ live API at checkout, snapshotted on the order | `catalog_products` is a browse mirror, not authoritative |
| Order total / fees | `orders` row written by `createOrder` | Flat 7% (`SERVICE_FEE_RATE`) |
| Payment status | IntaSend, re-verified → `orders.payment_status` | Client never writes it |
| Fulfilment / tracking | CJ → `orders.cj_*`, `orders.tracking` | |
| Money movements | `ledger_entries` (append-only) | M4, §6 |
| Who changed what | `audit_logs` (append-only) | M3, §6 |

---

## 4. Recommended order of work

1. **Batch A: stop money leaks (H1–H7).** One new migration plus changes to `orders.js`,
   `subscriptions.js` and `handler.ts`, each with RLS/Deno tests. H1 and H6 each need one product
   decision (see below).
2. **Batch B: accountability (M3, M4, M5, M6).** Audit log, ledger, webhook store, and a single fee
   source. Required before any payout code.
3. **Batch C: abuse and hygiene (M1, M2, M7, M8, M9, L1–L5).**
4. **Owner steps (not code):** everything in TODO.md's Supabase checklist, then a staging project,
   a live IntaSend sandbox run to settle M1, and a CJ sandbox run to confirm response shapes.

## 5. Production readiness

| Item | State |
|---|---|
| Auth, RLS on every table, admin via app_metadata, secrets out of the client | **READY** (in code) |
| Server-side pricing, payment re-verification, CJ push idempotency | **READY** (in code, unverified live) |
| Seller standing and plan-limit enforcement (H3–H6) | **READY** (in code, §6) |
| Seller revenue / fee correctness (H1, H2, M6) | **READY** (in code, §6) |
| Order state integrity (H7, M7) | **READY** (in code, §6) |
| Audit log, ledger, webhook store (M3–M5) | **READY** (in code, §6) |
| Public endpoint rate limiting (M2) | **READY** (in code, §6) |
| The fixes above applied to the real project | **REQUIRES MANUAL CONFIGURATION** (TODO.md rollout order) |
| Migrations applied, function deployed, secrets set, Vault, webhook URL, plans seeded | **REQUIRES MANUAL CONFIGURATION** |
| IntaSend/CJ response shapes confirmed against real accounts | **REQUIRES MANUAL CONFIGURATION** |
| Staging environment, backups (Supabase PITR), hosting decision | **REQUIRES MANUAL CONFIGURATION** |

**Sellora is not production-ready.** Every finding in §2 is now closed in code (§6), but none of it
has run against the real project, CJ or IntaSend. The remaining items are the manual rows above.
No design can make the system unhackable. The aim is defence in depth: RLS plus column grants plus
guard triggers at the database, re-verification at the function, and nothing trusted from the client.

---

## 6. Remediation (26 September 2026)

All of §2 was implemented in one pass. The schema side is one migration,
`supabase/migrations/20260928000000_security_hardening.sql`, checked by the hardening section at the
end of `supabase/tests/rls.test.mjs`. The function side is in `supabase/functions/`, with Deno tests,
and the app followed. Suite at hand-off: 170 PGlite checks, 70 Deno tests (285 steps), `flutter
analyze` clean, and `flutter test` 51 passing plus the known `seller_shell_controller_test` failure.
Two product decisions were taken with the owner. H1: Sellora keeps the freight margin. M6: drop
`commission_percent`.

| Finding | Fix |
|---|---|
| H1 | `splitServiceFee(retail, supplier)`: seller revenue = retail − CJ goods cost − 7% fee. The freight margin is Sellora's. `seller_revenue` left the buyer-readable column grant (it now reveals the margin), and sellers and admin read it through a new `seller_orders` view. `createOrder`'s response no longer returns it. |
| H2 | `createOrder` refuses a line unless its price less the fee covers CJ's live unit cost (`lineRefusal`). `CHECK (sell_price >= 0)`. The import screen validates against the same floor, using the dearest variant. |
| H3 | `activate_subscription` records the payment but leaves a `suspended` seller suspended. `subscribeSeller` refuses a suspended seller up front. |
| H4 | `subscribeSeller` refuses non-sellers. `activate_subscription` raises (and rolls back) for a non-seller entry. |
| H5 | `seller_can_sell()` gates publishing in the `products` insert/update policies. Drafts and unlisting stay open. `seller_order_gate()` refuses checkout for an inactive, suspended or lapsed seller. The storefront view hides a lapsed seller's catalog. |
| H6 | A trigger enforces `listing_limit` on publish (listed rows only, serialized per seller). The stores insert policy enforces `store_limit`. `seller_order_gate` enforces `order_limit` over paid orders in a rolling billing period. |
| H7 | The `orders_guard_status` trigger allows clients only processing→shipped→delivered, and only on a paid order. An admin may also cancel an unpaid order. Paid orders are cancelled only by the refund path. `fulfillOrder` parks a paid-but-cancelled order for reconciliation instead of shipping it. The seller UI no longer offers "Start processing" on an unpaid order. |
| M1 | `verifyAmount` fails closed. An unreadable amount raises the new `payment_amount_unverified` alert and holds the payment for a human. |
| M2 | Per-IP budgets (`publicCatalog`, `webhook`) keyed on `x-forwarded-for`. Browsing still calls CJ live. Serving it from `catalog_products` remains a worthwhile optimisation, not a security gap. |
| M3 | `audit_logs` (admin-read, append-only even for the owner) is written by triggers on profiles, plans, stores (non-owner edits), orders and billing, and by the refund and account-deletion paths with their actor. |
| M4 | `ledger_entries` (append-only, idempotent unique keys) is written by triggers in the same transaction as the state change: `ORDER_PAYMENT`, `PLATFORM_FEE`, `SUPPLIER_COST` and `SELLER_EARNING` on payment, `REFUND` per refund, and `SUBSCRIPTION_PAYMENT`. Refunds are booked but seller earnings are not reversed. A payout job must net them. |
| M5 | `webhook_events`, unique `(provider, invoice_id, state)`. It is written before handling, and the outcome is written after. |
| M6 | `subscription_plans.commission_percent` dropped from schema, model, admin UI and marketing copy. The flat 7% is the only fee. |
| M7 | `orders.expires_at` (60 min). Payment can't start after it. The `expire_unpaid_orders()` pg_cron sweep (every 15 min) cancels expired unpaid orders, giving 24 h of grace to one with a payment in flight. |
| M8 | `products` is readable only by its owner and admin. Buyers read `storefront_products`, which has no `cost_price` and strips each variant's `costPrice`. It is read-only (auto-update revoked). `sold_count`/`rating` are server-owned. `productDetail` now reads CJ directly rather than another store's listing. |
| M9 | `createOrder` checks CJ variant stock (`getProductStock`) and refuses a known shortfall. Unknown stock is not treated as zero. |
| L1 | `storeProducts`/`storefrontFeed` page with `.range()`, 60 at a time, with "Load more" on the storefront. |
| L2 | `POST /deleteAccount` calls `delete_account_data()`, which scrubs the profile, membership and delivery addresses, deletes notifications, and unlists a seller and suspends them. It then soft-deletes the Auth user. It is refused while a paid order is in fulfilment. Orders, billing and ledger rows are kept. There is a "Delete account" button on both profile screens. Google Play also wants a web link for deletion, which is not done. |
| L3 | Length `CHECK`s (NOT VALID, so they bind new writes only) on notifications, profile, store, customer and product free text. |
| L4 | A trigger on `auth.users` email changes updates `profiles.email` and `store_customers.email`. |
| L5 | `TRUNCATE`/`TRIGGER`/`REFERENCES` revoked from `anon`/`authenticated` on all public tables. |
| L6 | No change: CORS `*` with bearer-token auth, as noted. |
| L7 | An early renewal extends `current_period_end` from the current end. |

Still to settle when real accounts exist: IntaSend's status-response amount path (M1 now blocks
fulfilment if it's wrong), and CJ's stock field names (M9 falls back to "unknown").
