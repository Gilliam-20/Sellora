-- PHASE 10/12 (2026-10-03): per-store suspension, server-side platform
-- metrics for the admin Overview, and a client error log.
-- Checks: the 'store suspension', 'platform metrics' and 'client errors'
-- sections of supabase/tests/rls.test.mjs.

-- ---------------------------------------------------------------------------
-- Store suspension
-- ---------------------------------------------------------------------------

-- profiles.seller_status suspends a seller everywhere. This takes one store
-- offline (a policy problem with that storefront) without touching the
-- seller's account or billing. A suspended store's catalog drops out of
-- storefront_products, createOrder refuses it (_shared/orders.js), and the
-- storefront shows it as unavailable.
alter table public.stores
  add column is_suspended boolean not null default false,
  -- Public like the rest of the row: write it for the seller to read.
  add column suspension_reason text check (char_length(suspension_reason) <= 500),
  add column suspended_at timestamptz;

-- Replaces 20260926000000_initial_schema.sql's version: suspension is
-- admin-only on top of the existing immutable id/slug/owner.
create or replace function public.stores_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_privileged() then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.slug is distinct from old.slug
     or new.seller_id is distinct from old.seller_id
     or new.created_at is distinct from old.created_at then
    raise exception 'store id, slug and owner are immutable' using errcode = '42501';
  end if;
  if not public.is_admin()
     and (new.is_suspended is distinct from old.is_suspended
          or new.suspension_reason is distinct from old.suspension_reason
          or new.suspended_at is distinct from old.suspended_at) then
    raise exception 'only an admin may suspend a store' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- A seller creating a store can't create it pre-suspended either way it
-- matters, but nor should a client be able to write the admin's fields.
create or replace function public.stores_guard_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_privileged() and not public.is_admin() then
    new.is_suspended := false;
    new.suspension_reason := null;
    new.suspended_at := null;
  end if;
  return new;
end;
$$;

create trigger stores_guard_insert
  before insert on public.stores
  for each row execute function public.stores_guard_insert();

-- Same columns as 20260928000000_security_hardening.sql's view; only the
-- filter gains the store check.
create or replace view public.storefront_products with (security_barrier = true) as
select
  p.store_id, p.id, p.seller_id, p.cj_product_id, p.title, p.image_url,
  p.images, p.sell_price, p.compare_at_price, p.currency, p.category,
  p.description,
  coalesce((
    select jsonb_agg(
      case when jsonb_typeof(v) = 'object' then v - 'costPrice' else v end
      order by ord)
    from jsonb_array_elements(p.variants) with ordinality as e(v, ord)
  ), '[]'::jsonb) as variants,
  p.is_listed, p.sold_count, p.rating, p.stock, p.discount_percent,
  p.created_at
from public.products p
where p.is_listed
  and public.seller_can_sell(p.seller_id)
  and not exists (
    select 1 from public.stores s where s.id = p.store_id and s.is_suspended);

revoke all on public.storefront_products from public, anon, authenticated;
grant select on public.storefront_products to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Platform metrics for the admin Overview
-- ---------------------------------------------------------------------------

-- The Overview used to sum `orders.total` over the newest 200 orders the
-- client could read, adding KES, USD, GBP and EUR totals together. The
-- figures that are comparable across orders - `total_kes` (what IntaSend
-- actually charged), the USD fee snapshot and its FX rate - are
-- server-only columns, so the sums happen here, over every order, in KES.
--
-- Days are bucketed in Africa/Nairobi (EAT, no DST), Sellora's home market.
-- A refund is counted against GMV on the day it was ordered, not the day it
-- was refunded; refunds outside KES (none today: IntaSend settles in KES)
-- are left out of refundsKes rather than mixed in.
create or replace function public.admin_platform_metrics(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  days integer := least(greatest(coalesce(p_days, 30), 1), 366);
  today date := (now() at time zone 'Africa/Nairobi')::date;
  since date := today - (days - 1);
  result jsonb;
begin
  if not public.is_admin() then
    raise exception 'admin only' using errcode = '42501';
  end if;

  with paid as (
    select
      (o.created_at at time zone 'Africa/Nairobi')::date as day,
      coalesce(o.total_kes, 0) as gmv_kes,
      round(coalesce(o.service_fee_amount_usd, 0) * coalesce(o.fx_rate, 0), 2) as fee_kes,
      case when coalesce(o.refund_currency, 'KES') = 'KES'
           then coalesce(o.refunded_amount, 0) else 0 end as refund_kes
    from public.orders o
    where o.payment_status in ('paid', 'partially_refunded', 'refunded')
  ),
  series as (
    select d::date as day,
           coalesce(sum(p.gmv_kes), 0) as gmv_kes,
           coalesce(sum(p.fee_kes), 0) as fee_kes,
           count(p.day) as orders
    from generate_series(since, today, interval '1 day') d
    left join paid p on p.day = d::date
    group by d
  ),
  subs as (
    select s.*, pl.price_kes, pl.billing_period_days
    from public.subscriptions s
    left join public.subscription_plans pl on pl.id = s.plan_id
  )
  select jsonb_build_object(
    'days', days,
    'currency', 'KES',
    'lifetime', (select jsonb_build_object(
        'gmvKes', coalesce(sum(gmv_kes), 0),
        'serviceFeesKes', coalesce(sum(fee_kes), 0),
        'refundsKes', coalesce(sum(refund_kes), 0),
        'paidOrders', count(*)) from paid),
    'window', (select jsonb_build_object(
        'gmvKes', coalesce(sum(gmv_kes), 0),
        'serviceFeesKes', coalesce(sum(fee_kes), 0),
        'refundsKes', coalesce(sum(refund_kes), 0),
        'paidOrders', count(*)) from paid where day >= since),
    'series', (select coalesce(jsonb_agg(jsonb_build_object(
        'day', day, 'gmvKes', gmv_kes, 'serviceFeesKes', fee_kes, 'orders', orders)
        order by day), '[]') from series),
    'subscriptions', (select jsonb_build_object(
        'active', count(*) filter (where status = 'active' and current_period_end > now()),
        -- Lapsed in the last 30 days: the period ran out (or the row left
        -- 'active') without a renewal.
        'lapsed30d', count(*) filter (where not (status = 'active' and current_period_end > now())
                                     and current_period_end > now() - interval '30 days'),
        -- Normalized to 30 days, so a plan billed every 90 days counts a
        -- third of its price per month.
        'mrrKes', coalesce(round(sum(price_kes * 30.0 / greatest(billing_period_days, 1))
                  filter (where status = 'active' and current_period_end > now()), 2), 0)
      ) from subs)
  ) into result;
  return result;
end;
$$;

revoke execute on function public.admin_platform_metrics(integer) from public, anon;
grant execute on function public.admin_platform_metrics(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Client error log
-- ---------------------------------------------------------------------------

-- Uncaught errors from the app (FlutterError.onError and
-- PlatformDispatcher.onError, see lib/core/monitoring/error_reporter.dart),
-- so a crash in a buyer's browser is visible somewhere. Not a replacement
-- for a crash-reporting service; it's what exists until one is chosen.
-- Admin reads; nobody writes except through report_client_error.
create table public.client_errors (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  user_id uuid,
  -- Groups repeats of one error in the admin list.
  fingerprint text not null,
  message text not null,
  stack text,
  -- route, platform, release: whatever the app knew, size-capped.
  context jsonb not null default '{}'
);

create index client_errors_occurred_idx on public.client_errors (occurred_at desc);

alter table public.client_errors enable row level security;

create policy "client_errors: admin reads"
  on public.client_errors for select
  using ((select public.is_admin()));

revoke insert, update, delete on public.client_errors from anon, authenticated;

-- Signed-in users get 30 reports an hour each; signed-out visitors share
-- one budget of 300 an hour, so a crash loop on a public storefront can't
-- fill the table. Over budget, a report is dropped silently: the app
-- mustn't fail because its error report did.
create or replace function public.report_client_error(
  p_message text, p_stack text default null, p_context jsonb default '{}')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  allowed boolean;
  msg text := left(coalesce(nullif(btrim(p_message), ''), 'unknown error'), 2000);
  ctx jsonb := case when jsonb_typeof(p_context) = 'object'
                     and octet_length(p_context::text) <= 2048
                    then p_context else '{}'::jsonb end;
begin
  if uid is null then
    select l.allowed into allowed from public.consume_rate_limit('client_error:anon', 300, 3600000) l;
  else
    select l.allowed into allowed from public.consume_rate_limit('client_error:' || uid, 30, 3600000) l;
  end if;
  if not allowed then
    return;
  end if;
  insert into public.client_errors (user_id, fingerprint, message, stack, context)
  values (uid, md5(split_part(msg, E'\n', 1)), msg, left(p_stack, 8000), ctx);
end;
$$;

revoke execute on function public.report_client_error(text, text, jsonb) from public;
grant execute on function public.report_client_error(text, text, jsonb) to anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed: client error retention not scheduled';
    return;
  end if;
  -- Daily: keeps 30 days of client errors.
  perform cron.schedule('sellora-expire-client-errors', '20 4 * * *',
    $job$ delete from public.client_errors where occurred_at < now() - interval '30 days' $job$);
end;
$$;
