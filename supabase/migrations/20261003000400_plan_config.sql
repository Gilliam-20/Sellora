-- Subscription plans as admin configuration (TODO.md §16). The limits were
-- already enforced server-side (listing trigger, order gate, store policy)
-- but the table started empty, admins could only edit some of it, and
-- nothing stopped a nonsense value. This adds what §16 lists that wasn't a
-- column yet, bounds every field, and seeds the three launch plans.
--
-- Prices are charged in KES: subscribeSeller snapshots price_kes and both
-- payment routes charge KES, the only currency Sellora settles in today.
-- price_usd is the reference price shown alongside it, not a second charge
-- currency.

alter table public.subscription_plans
  -- A promise to the seller, not a software switch.
  add column support_level text not null default 'standard',
  -- false = retired: no longer offered or sold to new subscribers. Sellers
  -- already on it keep it and may renew (subscribeSeller checks).
  add column is_active boolean not null default true,
  -- Display order on every plan list; ties fall back to price.
  add column sort_order integer not null default 0,
  add constraint subscription_plans_id_format
    check (id ~ '^[a-z0-9][a-z0-9_-]{1,31}$'),
  add constraint subscription_plans_name_length
    check (length(btrim(name)) between 1 and 40),
  add constraint subscription_plans_prices
    check (price_kes >= 0 and price_usd >= 0),
  add constraint subscription_plans_period
    check (billing_period_days between 1 and 366),
  -- -1 is unlimited. A store limit of 0 would leave a seller without the
  -- store their account was created with.
  add constraint subscription_plans_limits
    check (listing_limit >= -1 and order_limit >= -1
           and (store_limit = -1 or store_limit >= 1)),
  add constraint subscription_plans_support_level
    check (support_level in ('standard', 'priority', 'dedicated')),
  add constraint subscription_plans_perks
    check (cardinality(perks) <= 12),
  -- Feature flags: an object of booleans, read by key.
  add constraint subscription_plans_features
    check (jsonb_typeof(features) = 'object'
           and not jsonb_path_exists(features, '$.* ? (@.type() != "boolean")'));

-- The launch plans from TODO.md §16. `do nothing`, so re-running this (or
-- running it after an admin has already set plans up) never overwrites an
-- admin's edits.
insert into public.subscription_plans (
  id, name, price_kes, price_usd, billing_period_days,
  listing_limit, order_limit, store_limit,
  support_level, is_popular, sort_order, features, perks)
values
  ('starter', 'Starter', 1300, 10, 30, 50, 100, 1,
   'standard', false, 10,
   '{"customDomain": false, "advancedAnalytics": false}', '{}'),
  ('growth', 'Growth', 4000, 31, 30, 500, 1000, 3,
   'priority', true, 20,
   '{"customDomain": false, "advancedAnalytics": true}', '{}'),
  ('pro', 'Pro', 10300, 80, 30, -1, -1, 10,
   'dedicated', false, 30,
   '{"customDomain": true, "advancedAnalytics": true}', '{}')
on conflict (id) do nothing;
