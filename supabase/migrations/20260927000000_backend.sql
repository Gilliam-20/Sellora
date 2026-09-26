-- Sellora on Supabase — Phase 2 schema: what the backend (the `api` Edge
-- Function, supabase/functions/) reads and writes that no client does.
--
-- Ported from the Firestore documents functions/ used to keep: the order
-- document's payment/fulfilment/refund bookkeeping, the shared CJ catalog,
-- config/pricing + config/catalog, cj_config/auth_token, and rate_limits.
-- Firestore transactions become either a compare-and-set UPDATE in the Edge
-- Function (order push/refund claims) or one of the SQL functions below,
-- which do a multi-row change atomically. See WORKLOG.md, 2026-09-27.

-- ---------------------------------------------------------------------------
-- orders: server-owned bookkeeping
-- ---------------------------------------------------------------------------

-- The Firestore port wrote 'AWAITING_CONFIRMATION' / 'refunded' /
-- 'partially_refunded' onto orders; the phase 1 check only allowed the
-- three states the app had.
alter table public.orders drop constraint orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
  check (payment_status in (
    'pending', 'awaiting_confirmation', 'paid', 'failed',
    'partially_refunded', 'refunded'));

alter table public.orders
  -- Client-visible: the app renders these.
  add column payment_provider text,
  add column tracking jsonb,
  add column refunded_amount numeric(12, 2) not null default 0,
  -- Server-only from here down (see the column grant below). Figures a
  -- buyer must never see (the supplier cost is the seller's margin), and
  -- the state machines the backend drives.
  add column total_usd numeric(12, 2),
  add column total_kes numeric(12, 2),
  add column fx_rate numeric,
  add column supplier_subtotal_usd numeric(12, 2),
  add column supplier_freight_usd numeric(12, 2),
  add column retail_subtotal_usd numeric(12, 2),
  add column retail_freight_usd numeric(12, 2),
  add column service_fee_amount_usd numeric(12, 2),
  add column seller_revenue_usd numeric(12, 2),
  add column estimated_profit_usd numeric(12, 2),
  -- Was the orders/{id}/items subcollection: per-line USD supplier/retail
  -- prices and SKUs.
  add column lines jsonb not null default '[]',
  -- [{pid, vid, quantity}] exactly as pushed to CJ.
  add column fulfillment_items jsonb not null default '[]',
  add column payment_ref jsonb,
  add column payment_attempts jsonb not null default '[]',
  add column last_payment_attempt_at timestamptz,
  add column cj_order_status text not null default 'NOT_PUSHED'
    check (cj_order_status in (
      'NOT_PUSHED', 'PUSHING', 'PUSHED', 'FAILED', 'NEEDS_RECONCILIATION')),
  add column cj_order_id text,
  add column cj_order_number text,
  add column cj_push_attempts integer not null default 0,
  add column cj_push_claimed_at timestamptz,
  add column cj_order_error text,
  add column cj_last_failed_at timestamptz,
  add column tracking_checked_at timestamptz,
  add column tracking_complete boolean not null default false,
  add column refund_status text not null default 'NONE'
    check (refund_status in ('NONE', 'PROCESSING', 'REFUNDED', 'FAILED')),
  add column refund_claimed_at timestamptz,
  add column refund_error text,
  add column refund_currency text,
  add column refunds jsonb not null default '[]';

-- retryFailedFulfillments / refreshTrackingBatch scans.
create index orders_fulfilment_retry_idx on public.orders (cj_order_status)
  where payment_status = 'paid' and cj_order_status in ('FAILED', 'PUSHING');
create index orders_tracking_poll_idx on public.orders (tracking_checked_at nulls first)
  where cj_order_status = 'PUSHED' and not tracking_complete;

-- Row-level security decides *which* orders a buyer/seller sees; this
-- decides which columns. A client select must name its columns
-- (SupabaseOrderRepository.columns) — `select *` is refused outright,
-- which is the point: a new server-only column can't leak by default.
revoke select on public.orders from anon, authenticated;
grant select (
  id, code, buyer_id, seller_id, store_id, items, status, total, currency,
  shipping_address, payment_method, payment_reference, tracking_number,
  payment_status, service_fee_rate, service_fee_amount, seller_revenue,
  payment_fee, shipping_fee, logistic_name, created_at, updated_at,
  payment_provider, tracking, refunded_amount
) on public.orders to authenticated;

-- Records a payment attempt: the latest one on payment_ref, and every one
-- on payment_attempts, so a late webhook for an earlier attempt still
-- matches (orders.paymentRefMatches). One statement, so two attempts
-- racing can't drop each other from the history. An order that is already
-- paid or refunded is left alone — a webhook can land between the Edge
-- Function's payability check and this write.
create or replace function public.attach_order_payment_attempt(
  p_order_id text, p_method text, p_provider text, p_ref jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.orders
  set payment_method = p_method,
      payment_provider = p_provider,
      payment_ref = p_ref,
      payment_status = 'awaiting_confirmation',
      payment_attempts = payment_attempts || jsonb_build_array(jsonb_build_object(
        'paymentMethod', p_method,
        'paymentProvider', p_provider,
        'paymentRef', p_ref,
        'createdAt', now())),
      last_payment_attempt_at = now(),
      updated_at = now()
  where id = p_order_id
    and payment_status in ('pending', 'awaiting_confirmation', 'failed');
  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- billing_history: payment attempt + atomic activation
-- ---------------------------------------------------------------------------

alter table public.billing_history
  add column payment_method text,
  add column payment_ref jsonb;

-- Was subscriptions.activatePendingSubscription's Firestore batch: marks the
-- entry paid, upserts the seller's subscription and mirrors it onto their
-- profile, all or nothing. Idempotent — the status='pending' guard is what
-- makes a retried webhook a no-op instead of a second period.
create or replace function public.activate_subscription(
  p_entry_id text, p_payment_reference text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry public.billing_history;
  plan_order_limit integer;
  period_start timestamptz := now();
  period_end timestamptz;
begin
  update public.billing_history
  set status = 'paid', payment_reference = p_payment_reference, paid_at = period_start
  where id = p_entry_id and status = 'pending'
  returning * into entry;

  if not found then
    select * into entry from public.billing_history where id = p_entry_id;
    if not found then
      raise exception 'billing entry % not found', p_entry_id using errcode = 'P0002';
    end if;
    return jsonb_build_object(
      'alreadyHandled', true, 'sellerId', entry.seller_id, 'planId', entry.plan_id);
  end if;

  select order_limit into plan_order_limit
  from public.subscription_plans where id = entry.plan_id;
  period_end := period_start + make_interval(days => entry.billing_period_days);

  insert into public.subscriptions as s (
    seller_id, plan_id, status, order_limit, current_period_start,
    current_period_end, last_billing_history_id, updated_at)
  values (
    entry.seller_id, entry.plan_id, 'active', coalesce(plan_order_limit, -1),
    period_start, period_end, entry.id, period_start)
  on conflict (seller_id) do update set
    plan_id = excluded.plan_id,
    status = excluded.status,
    order_limit = excluded.order_limit,
    current_period_start = excluded.current_period_start,
    current_period_end = excluded.current_period_end,
    last_billing_history_id = excluded.last_billing_history_id,
    updated_at = excluded.updated_at;

  update public.profiles
  set subscription_plan_id = entry.plan_id,
      subscription_active_until = period_end,
      seller_status = 'active'
  where uid = entry.seller_id;

  return jsonb_build_object(
    'alreadyHandled', false,
    'sellerId', entry.seller_id,
    'planId', entry.plan_id,
    'currentPeriodEnd', period_end);
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared CJ catalog (was top-level `products` + `categories`)
-- ---------------------------------------------------------------------------

-- Mirrored daily from CJ by the syncCatalog job. Public, like the Firestore
-- collections were: it's the browse catalog, and every figure in it
-- (supplier price included) is already public from searchProducts.
create table public.catalog_categories (
  id text primary key,
  name text not null,
  parent_id text not null default '',
  level integer not null default 0,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  is_featured boolean not null default false,
  source text not null default 'cj',
  updated_at timestamptz not null default now()
);

alter table public.catalog_categories enable row level security;

create policy "catalog_categories: public read"
  on public.catalog_categories for select
  using (true);

create table public.catalog_products (
  id text primary key,
  title text not null default '',
  sku text not null default '',
  thumbnail_url text not null default '',
  price_min numeric(12, 2) not null default 0,
  compare_at_price_min numeric(12, 2) not null default 0,
  supplier_price_usd numeric(12, 2) not null default 0,
  primary_category_id text not null default '',
  category_name text not null default '',
  product_type text not null default 'cj',
  stock_available integer not null default 0,
  source text not null default 'cj',
  cj_product_id text,
  is_active boolean not null default true,
  is_featured boolean not null default false,
  featured_rank integer not null default 1000,
  sync_run_id text,
  last_synced_at timestamptz,
  -- Filled in progressively by enrichProducts (null = not yet).
  description text,
  image_urls text[] not null default '{}',
  variants jsonb not null default '[]',
  product_attributes jsonb not null default '[]',
  videos jsonb not null default '[]',
  detail_synced_at timestamptz,
  detail_sync_error boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index catalog_products_active_idx
  on public.catalog_products (is_active, featured_rank, created_at desc);
create index catalog_products_category_idx
  on public.catalog_products (primary_category_id) where is_active;
create index catalog_products_needs_detail_idx
  on public.catalog_products (created_at) where detail_synced_at is null;

alter table public.catalog_products enable row level security;

create policy "catalog_products: public read"
  on public.catalog_products for select
  using (true);

-- ---------------------------------------------------------------------------
-- app_config (was config/pricing + config/catalog)
-- ---------------------------------------------------------------------------

-- key 'pricing': margin/fee/rounding config (pricing.js getPricing).
-- key 'catalog': the CJ sources to mirror (catalogSync.js getCatalogConfig).
-- Absent keys fall back to the defaults in code.
create table public.app_config (
  key text primary key check (key in ('pricing', 'catalog')),
  value jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;

create policy "app_config: admin reads and writes"
  on public.app_config for all
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------------------------------------------------------------------------
-- cj_auth_tokens (was cj_config/auth_token) — service role only
-- ---------------------------------------------------------------------------

-- One row. No policies: RLS on with nothing granted means only the service
-- role (the Edge Function) can see it. These are live CJ credentials.
create table public.cj_auth_tokens (
  id text primary key default 'current' check (id = 'current'),
  access_token text not null,
  access_token_expiry_date text,
  refresh_token text,
  refresh_token_expiry_date text,
  updated_at timestamptz not null default now()
);

alter table public.cj_auth_tokens enable row level security;

-- ---------------------------------------------------------------------------
-- rate_limits — service role only
-- ---------------------------------------------------------------------------

-- Fixed-window counters, `{policy}:{uid}` -> window. Replaces the Firestore
-- `rate_limits` collection and its TTL policy (the cleanup is a pg_cron job
-- in the next migration).
create table public.rate_limits (
  key text primary key,
  window_start timestamptz not null,
  count integer not null,
  expire_at timestamptz not null
);

alter table public.rate_limits enable row level security;

-- Counts one call against `p_key`'s budget. The row lock is what the
-- Firestore transaction was for: concurrent calls from one user serialize
-- here instead of each reading the same count.
create or replace function public.consume_rate_limit(
  p_key text, p_limit integer, p_window_ms bigint)
returns table (allowed boolean, retry_after_ms bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_ts timestamptz := clock_timestamp();
  win interval := make_interval(secs => p_window_ms / 1000.0);
  current_row public.rate_limits;
begin
  insert into public.rate_limits (key, window_start, count, expire_at)
  values (p_key, now_ts, 0, now_ts + win)
  on conflict (key) do nothing;

  select * into current_row from public.rate_limits where key = p_key for update;

  if now_ts - current_row.window_start >= win then
    current_row.window_start := now_ts;
    current_row.count := 0;
  end if;

  if current_row.count >= p_limit then
    return query select false,
      greatest(0, ceil(extract(epoch from (current_row.window_start + win - now_ts)) * 1000))::bigint;
    return;
  end if;

  update public.rate_limits
  set window_start = current_row.window_start,
      count = current_row.count + 1,
      expire_at = current_row.window_start + win
  where key = p_key;
  return query select true, 0::bigint;
end;
$$;

-- ---------------------------------------------------------------------------
-- Server-only functions are callable by the service role alone
-- ---------------------------------------------------------------------------

revoke execute on function public.attach_order_payment_attempt(text, text, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.activate_subscription(text, text)
  from public, anon, authenticated;
revoke execute on function public.consume_rate_limit(text, integer, bigint)
  from public, anon, authenticated;
grant execute on function public.attach_order_payment_attempt(text, text, text, jsonb)
  to service_role;
grant execute on function public.activate_subscription(text, text) to service_role;
grant execute on function public.consume_rate_limit(text, integer, bigint) to service_role;
