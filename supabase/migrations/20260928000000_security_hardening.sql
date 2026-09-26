-- Sellora on Supabase — security hardening from SELLORA_SECURITY_AUDIT.md
-- (26 September 2026). Each section names the finding it closes; the
-- matching checks are at the end of supabase/tests/rls.test.mjs.
--
-- Constraints added to existing tables are NOT VALID: they bind every new
-- insert and update from now on without failing the migration on a row
-- written before they existed.

-- ---------------------------------------------------------------------------
-- Seller standing (H5)
-- ---------------------------------------------------------------------------

-- Whether a seller may sell right now: an approved (active, not suspended)
-- seller with an unexpired active subscription. Enforcement used to live in
-- RoleMiddleware only, i.e. in the client. Used by the products policies and
-- the storefront view; clients need execute for the policies to evaluate,
-- and all it reveals is what a storefront shows anyway.
create or replace function public.seller_can_sell(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.subscriptions s on s.seller_id = p.uid
    where p.uid = p_seller_id
      and p.role = 'seller'
      and p.seller_status = 'active'
      and s.status = 'active'
      and s.current_period_end > now())
$$;

-- What createOrder asks before it prices anything: 'ok', or why this
-- seller can't take an order (H5), including a spent plan order_limit (H6).
-- The limit counts paid orders over a rolling billing period, so an early
-- renewal (see activate_subscription) can't reset it, and unpaid orders a
-- stranger creates can't use it up.
create or replace function public.seller_order_gate(p_seller_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  seller public.profiles;
  sub public.subscriptions;
  period_days integer;
  paid_orders integer;
begin
  select * into seller from public.profiles where uid = p_seller_id;
  if not found or seller.role <> 'seller' then
    return 'not_a_seller';
  end if;
  if seller.seller_status is distinct from 'active' then
    return 'seller_inactive';
  end if;
  select * into sub from public.subscriptions where seller_id = p_seller_id;
  if not found or sub.status <> 'active' or sub.current_period_end <= now() then
    return 'subscription_lapsed';
  end if;
  if sub.order_limit >= 0 then
    select billing_period_days into period_days
    from public.subscription_plans where id = sub.plan_id;
    select count(*) into paid_orders
    from public.orders
    where seller_id = p_seller_id
      and payment_status in ('paid', 'partially_refunded', 'refunded')
      and created_at > now() - make_interval(days => coalesce(period_days, 30));
    if paid_orders >= sub.order_limit then
      return 'order_limit_reached';
    end if;
  end if;
  return 'ok';
end;
$$;

-- ---------------------------------------------------------------------------
-- Subscriptions: who may activate, and what activation may change (H3, H4, L7)
-- ---------------------------------------------------------------------------

-- Replaces 20260927000000_backend.sql's version. Differences:
--   * H4: the entry must belong to a seller. subscribeSeller already refuses
--     anyone else; this is the backstop.
--   * H3: payment approves a pending seller but never lifts a suspension.
--     The payment is still recorded and the period still granted - the
--     money was taken - but seller_status stays 'suspended' until an admin
--     changes it.
--   * L7: renewing before the current period ends extends it from its end
--     instead of restarting it now, so the seller keeps the days they paid for.
create or replace function public.activate_subscription(
  p_entry_id text, p_payment_reference text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry public.billing_history;
  seller public.profiles;
  existing public.subscriptions;
  plan_order_limit integer;
  paid_time timestamptz := now();
  period_start timestamptz;
  period_end timestamptz;
  next_status text;
begin
  update public.billing_history
  set status = 'paid', payment_reference = p_payment_reference, paid_at = paid_time
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

  select * into seller from public.profiles where uid = entry.seller_id for update;
  if not found or seller.role <> 'seller' then
    raise exception 'billing entry % does not belong to a seller', p_entry_id
      using errcode = '42501';
  end if;

  select order_limit into plan_order_limit
  from public.subscription_plans where id = entry.plan_id;

  select * into existing from public.subscriptions
  where seller_id = entry.seller_id for update;
  if found and existing.status = 'active' and existing.current_period_end > paid_time then
    period_start := existing.current_period_start;
    period_end := existing.current_period_end + make_interval(days => entry.billing_period_days);
  else
    period_start := paid_time;
    period_end := paid_time + make_interval(days => entry.billing_period_days);
  end if;

  insert into public.subscriptions as s (
    seller_id, plan_id, status, order_limit, current_period_start,
    current_period_end, last_billing_history_id, updated_at)
  values (
    entry.seller_id, entry.plan_id, 'active', coalesce(plan_order_limit, -1),
    period_start, period_end, entry.id, paid_time)
  on conflict (seller_id) do update set
    plan_id = excluded.plan_id,
    status = excluded.status,
    order_limit = excluded.order_limit,
    current_period_start = excluded.current_period_start,
    current_period_end = excluded.current_period_end,
    last_billing_history_id = excluded.last_billing_history_id,
    updated_at = excluded.updated_at;

  next_status := case when seller.seller_status = 'suspended' then 'suspended' else 'active' end;
  update public.profiles
  set subscription_plan_id = entry.plan_id,
      subscription_active_until = period_end,
      seller_status = next_status
  where uid = entry.seller_id;

  return jsonb_build_object(
    'alreadyHandled', false,
    'sellerId', entry.seller_id,
    'planId', entry.plan_id,
    'sellerStatus', next_status,
    'currentPeriodEnd', period_end);
end;
$$;

-- ---------------------------------------------------------------------------
-- Products: price floor, standing, plan limits, server-owned counters (H2, H5, H6, M8)
-- ---------------------------------------------------------------------------

-- H2: the database-level floor. The real one - price covers CJ's live cost
-- plus the fee - is checked per line in createOrder, since only the server
-- knows CJ's cost; cost_price here is seller-written.
alter table public.products
  add constraint products_sell_price_nonnegative check (sell_price >= 0) not valid,
  add constraint products_cost_price_nonnegative check (cost_price >= 0) not valid;

-- H5: only a seller in good standing may publish. Drafts stay writable, and
-- so does unlisting, so a lapsed seller can still tidy their store.
drop policy "products: store owner creates" on public.products;
create policy "products: store owner creates"
  on public.products for insert
  with check (
    seller_id = (select auth.uid())
    and public.owns_store(store_id)
    and (not is_listed or public.seller_can_sell(seller_id)));

drop policy "products: store owner updates" on public.products;
create policy "products: store owner updates"
  on public.products for update
  using (public.owns_store(store_id))
  with check (
    seller_id = (select auth.uid())
    and public.owns_store(store_id)
    and (not is_listed or public.seller_can_sell(seller_id)));

-- M8: the table is no longer publicly readable - a listed row carried the
-- seller's cost_price (and each variant's costPrice), i.e. their margin.
-- Buyers read storefront_products below instead.
drop policy "products: listed public, drafts owner-only" on public.products;
create policy "products: owner or admin reads"
  on public.products for select
  using (public.owns_store(store_id) or (select public.is_admin()));

-- M8: sold_count and rating are social proof, so a seller can't set them.
-- Silently kept rather than refused: the app upserts whole ProductModel
-- maps, which carry both fields back unchanged.
create or replace function public.products_guard_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_privileged() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.sold_count := 0;
    new.rating := 0;
    return new;
  end if;
  if new.store_id is distinct from old.store_id
     or new.id is distinct from old.id
     or new.created_at is distinct from old.created_at then
    raise exception 'listing store, id and creation time are immutable' using errcode = '42501';
  end if;
  new.sold_count := old.sold_count;
  new.rating := old.rating;
  return new;
end;
$$;

create trigger products_guard_write
  before insert or update on public.products
  for each row execute function public.products_guard_write();

-- H6: listed products count against the seller's plan listing_limit, across
-- all their stores. Drafts are free. The profile row lock serializes one
-- seller's concurrent publishes, so two can't both take the last slot.
-- No subscription means no plan to read; the publish policy above already
-- refuses that seller.
create or replace function public.products_enforce_listing_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  listing_cap integer;
  listed integer;
begin
  if not new.is_listed or (tg_op = 'UPDATE' and old.is_listed) then
    return new;
  end if;
  perform 1 from public.profiles where uid = new.seller_id for update;
  select pl.listing_limit into listing_cap
  from public.subscriptions s
  join public.subscription_plans pl on pl.id = s.plan_id
  where s.seller_id = new.seller_id;
  if listing_cap is null or listing_cap < 0 then
    return new;
  end if;
  select count(*) into listed
  from public.products
  where seller_id = new.seller_id
    and is_listed
    and not (store_id = new.store_id and id = new.id);
  if listed >= listing_cap then
    raise exception 'listing limit reached: your plan allows % listed products', listing_cap
      using errcode = 'P0001', hint = 'listing_limit';
  end if;
  return new;
end;
$$;

create trigger products_enforce_listing_limit
  before insert or update on public.products
  for each row execute function public.products_enforce_listing_limit();

-- M8: what buyers (and anyone browsing) read. Listed products of sellers in
-- good standing only (H5: a lapsed store stops showing its catalog), with
-- cost_price left out and each variant's costPrice stripped.
--
-- A view runs with its owner's rights, so it reads past the owner-only
-- policy above; its WHERE clause is the whole filter. A simple view like
-- this is also auto-updatable, which would let a client write products
-- past RLS - hence the revoke before the select-only grant.
create view public.storefront_products with (security_barrier = true) as
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
where p.is_listed and public.seller_can_sell(p.seller_id);

revoke all on public.storefront_products from public, anon, authenticated;
grant select on public.storefront_products to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Stores: plan store_limit (H6)
-- ---------------------------------------------------------------------------

-- A seller with no subscription may still create their first store (the
-- onboarding recovery path); after that the plan's store_limit applies.
create or replace function public.seller_can_add_store(p_seller_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select pl.store_limit < 0
            or (select count(*) from public.stores where seller_id = p_seller_id) < pl.store_limit
     from public.subscriptions s
     join public.subscription_plans pl on pl.id = s.plan_id
     where s.seller_id = p_seller_id),
    (select count(*) from public.stores where seller_id = p_seller_id) < 1)
$$;

drop policy "stores: sellers create their own" on public.stores;
create policy "stores: sellers create their own"
  on public.stores for insert
  with check (
    seller_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.uid = (select auth.uid()) and p.role = 'seller'
    )
    and public.seller_can_add_store((select auth.uid())));

-- ---------------------------------------------------------------------------
-- Orders: status transitions, expiry, seller-only revenue (H1, H7, M7)
-- ---------------------------------------------------------------------------

-- H7: the column grant let a seller set any status. A client may now only
-- move a paid order forward through fulfilment. An admin may additionally
-- cancel an order nobody has paid for. A paid order is cancelled only by
-- the refund path (refundOrder), which runs as the service role, so the
-- buyer gets their money back.
create or replace function public.orders_guard_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_privileged() or new.status is not distinct from old.status then
    return new;
  end if;
  if new.payment_status = 'paid'
     and ((old.status = 'processing' and new.status = 'shipped')
          or (old.status = 'shipped' and new.status = 'delivered')) then
    return new;
  end if;
  if (select public.is_admin())
     and new.status = 'cancelled'
     and old.payment_status in ('pending', 'failed') then
    return new;
  end if;
  raise exception 'order status cannot move from % to %', old.status, new.status
    using errcode = '42501';
end;
$$;

create trigger orders_guard_status
  before update on public.orders
  for each row execute function public.orders_guard_status();

-- M7: an unpaid order holds a snapshot of CJ's cost and the FX rate, so it
-- can't stay payable forever. createOrder sets this; the api function
-- refuses to start a payment after it; the sweep below cancels the order.
alter table public.orders add column expires_at timestamptz;

create index orders_expiry_idx on public.orders (expires_at)
  where status = 'pending';

-- Cancels unpaid orders past their expiry. An order with a payment attempt
-- in flight gets a day's grace from that attempt: a payment started before
-- expiry is still honoured if it completes (see fulfillOrder, which parks a
-- paid-but-cancelled order for reconciliation instead of shipping it).
create or replace function public.expire_unpaid_orders()
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    update public.orders
    set status = 'cancelled', updated_at = now()
    where status = 'pending'
      and expires_at < now()
      and (payment_status in ('pending', 'failed')
           or (payment_status = 'awaiting_confirmation'
               and last_payment_attempt_at < now() - interval '24 hours'))
    returning 1)
  select count(*)::integer from expired
$$;

-- H1 made seller_revenue exact (retail - supplier cost - fee), which also
-- makes it the seller's margin. Buyers read the same `orders` columns as
-- sellers, so it moves off the shared grant onto a seller-only view.
revoke select (seller_revenue) on public.orders from authenticated;

create view public.seller_orders with (security_barrier = true) as
select
  o.id, o.code, o.buyer_id, o.seller_id, o.store_id, o.items, o.status,
  o.total, o.currency, o.shipping_address, o.payment_method,
  o.payment_reference, o.tracking_number, o.payment_status,
  o.service_fee_rate, o.service_fee_amount, o.seller_revenue, o.payment_fee,
  o.shipping_fee, o.logistic_name, o.created_at, o.updated_at,
  o.payment_provider, o.tracking, o.refunded_amount
from public.orders o
where o.seller_id = (select auth.uid())
   or public.owns_store(o.store_id)
   or (select public.is_admin());

revoke all on public.seller_orders from public, anon, authenticated;
grant select on public.seller_orders to authenticated;

-- ---------------------------------------------------------------------------
-- Plans: one fee source (M6)
-- ---------------------------------------------------------------------------

-- The flat 7% service fee (SERVICE_FEE_RATE in orders.js) is the only fee.
-- This column was shown as "X% commission" and charged nowhere.
alter table public.subscription_plans drop column commission_percent;

-- ---------------------------------------------------------------------------
-- Audit trail (M3)
-- ---------------------------------------------------------------------------

-- Append-only. Written by the triggers below and by the api function (the
-- refund and account-deletion paths, which know the acting admin/user).
-- No client may write it; nobody may change or remove a row.
create table public.audit_logs (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  -- auth.uid() of the request, when there is one.
  actor_id uuid,
  -- 'admin' | 'user' (a signed-in client) | 'service' (the api function)
  -- | 'system' (SQL, cron).
  actor_role text not null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  details jsonb not null default '{}'
);

create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id, occurred_at desc);
create index audit_logs_occurred_idx on public.audit_logs (occurred_at desc);

alter table public.audit_logs enable row level security;

create policy "audit_logs: admin reads"
  on public.audit_logs for select
  using ((select public.is_admin()));

create or replace function public.current_actor_role()
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when public.is_admin() then 'admin'
    when auth.uid() is not null then 'user'
    when auth.jwt() ->> 'role' = 'service_role' then 'service'
    else 'system'
  end
$$;

-- {field: [old, new]} for each of `keys` (every key when null) that changed.
create or replace function public.jsonb_changes(old_row jsonb, new_row jsonb, keys text[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(k, jsonb_build_array(old_row -> k, new_row -> k)),
    '{}'::jsonb)
  from (
    select coalesce(keys, array(
      select jsonb_object_keys(coalesce(new_row, '{}'::jsonb) || coalesce(old_row, '{}'::jsonb))
    )) as ks
  ) src, unnest(src.ks) as k
  where (old_row -> k) is distinct from (new_row -> k)
$$;

create or replace function public.write_audit(
  p_action text, p_entity_type text, p_entity_id text, p_details jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (actor_id, actor_role, action, entity_type, entity_id, details)
  values (auth.uid(), public.current_actor_role(), p_action, p_entity_type, p_entity_id,
          coalesce(p_details, '{}'::jsonb));
$$;

-- Profiles: every change to role, standing, subscription mirror or store,
-- and every edit an admin makes to someone else's profile (setSellerStatus
-- is a plain update from the admin app).
create or replace function public.audit_profiles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sensitive jsonb := public.jsonb_changes(to_jsonb(old), to_jsonb(new), array[
    'role', 'seller_status', 'subscription_plan_id', 'subscription_active_until',
    'store_id', 'email']);
  everything jsonb;
begin
  if public.is_admin() and new.uid is distinct from auth.uid() then
    everything := public.jsonb_changes(to_jsonb(old), to_jsonb(new), null);
    if everything <> '{}'::jsonb then
      perform public.write_audit('profile.admin_update', 'profile', new.uid::text,
        jsonb_build_object('changes', everything));
    end if;
  elsif sensitive <> '{}'::jsonb then
    perform public.write_audit('profile.update', 'profile', new.uid::text,
      jsonb_build_object('changes', sensitive));
  end if;
  return new;
end;
$$;

create trigger audit_profiles
  after update on public.profiles
  for each row execute function public.audit_profiles();

create or replace function public.audit_plans()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.write_audit('plan.delete', 'subscription_plan', old.id,
      jsonb_build_object('before', to_jsonb(old)));
    return old;
  end if;
  if tg_op = 'INSERT' then
    perform public.write_audit('plan.create', 'subscription_plan', new.id,
      jsonb_build_object('after', to_jsonb(new)));
  else
    perform public.write_audit('plan.update', 'subscription_plan', new.id,
      jsonb_build_object('changes', public.jsonb_changes(to_jsonb(old), to_jsonb(new), null)));
  end if;
  return new;
end;
$$;

create trigger audit_plans
  after insert or update or delete on public.subscription_plans
  for each row execute function public.audit_plans();

-- Stores: edits by anyone other than the owner (an admin, the backend).
create or replace function public.audit_stores()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changes jsonb;
begin
  if auth.uid() is not distinct from new.seller_id then
    return new;
  end if;
  changes := public.jsonb_changes(to_jsonb(old), to_jsonb(new), null);
  if changes <> '{}'::jsonb then
    perform public.write_audit('store.update', 'store', new.id,
      jsonb_build_object('changes', changes));
  end if;
  return new;
end;
$$;

create trigger audit_stores
  after update on public.stores
  for each row execute function public.audit_stores();

-- Orders: every move of the money, fulfilment and refund state machines.
create or replace function public.audit_orders()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changes jsonb := public.jsonb_changes(to_jsonb(old), to_jsonb(new), array[
    'status', 'payment_status', 'refund_status', 'refunded_amount',
    'cj_order_status']);
begin
  if changes <> '{}'::jsonb then
    perform public.write_audit('order.update', 'order', new.id,
      jsonb_build_object('changes', changes));
  end if;
  return new;
end;
$$;

create trigger audit_orders
  after update on public.orders
  for each row execute function public.audit_orders();

create or replace function public.audit_billing()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    perform public.write_audit('billing.update', 'billing_history', new.id,
      jsonb_build_object('changes',
        public.jsonb_changes(to_jsonb(old), to_jsonb(new), array['status', 'payment_reference'])));
  end if;
  return new;
end;
$$;

create trigger audit_billing
  after update on public.billing_history
  for each row execute function public.audit_billing();

-- ---------------------------------------------------------------------------
-- Financial ledger (M4)
-- ---------------------------------------------------------------------------

-- Insert-only record of every money movement, written by triggers in the
-- same transaction as the state change that caused it. Payouts and
-- reports read this, not the mutable columns on orders/billing_history.
-- Amounts are always positive; entry_type says which way the money went.
create table public.ledger_entries (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  entry_type text not null check (entry_type in (
    'ORDER_PAYMENT', 'PLATFORM_FEE', 'SUPPLIER_COST', 'SELLER_EARNING',
    'REFUND', 'SUBSCRIPTION_PAYMENT')),
  order_id text references public.orders (id),
  billing_history_id text references public.billing_history (id),
  seller_id uuid references public.profiles (uid),
  amount numeric(14, 2) not null check (amount >= 0),
  currency text not null,
  -- USD equivalent, where the source row has one.
  amount_usd numeric(14, 2),
  -- What makes the entry unique within its order: the provider reference
  -- for a payment, the refunded total after it for a refund.
  reference text not null default '',
  details jsonb not null default '{}'
);

-- One of each order-level entry per order, one refund entry per refunded
-- total, one payment per billing entry: a retried trigger can't double-book.
create unique index ledger_entries_order_uniq
  on public.ledger_entries (entry_type, order_id, reference) where order_id is not null;
create unique index ledger_entries_billing_uniq
  on public.ledger_entries (entry_type, billing_history_id) where billing_history_id is not null;
create index ledger_entries_seller_idx on public.ledger_entries (seller_id, created_at desc);

alter table public.ledger_entries enable row level security;

create policy "ledger_entries: seller reads own, admin reads all"
  on public.ledger_entries for select
  using (seller_id = (select auth.uid()) or (select public.is_admin()));

-- A paid order books the charge and how it splits: the fee Sellora keeps,
-- what Sellora owes CJ, and what it owes the seller (H1). The remaining
-- freight margin is Sellora's (owner decision, 2026-09-26). A refund books
-- the amount returned.
create or replace function public.ledger_orders()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  charge_amount numeric := coalesce(new.total_kes, new.total);
  charge_currency text := case when new.total_kes is not null then 'KES' else new.currency end;
begin
  if new.payment_status = 'paid'
     and old.payment_status in ('pending', 'awaiting_confirmation', 'failed') then
    insert into public.ledger_entries
      (entry_type, order_id, seller_id, amount, currency, amount_usd, reference, details)
    values
      ('ORDER_PAYMENT', new.id, new.seller_id, charge_amount, charge_currency, new.total_usd,
       coalesce(new.payment_ref ->> 'invoiceId', new.payment_ref ->> 'checkoutId', ''),
       jsonb_build_object('provider', new.payment_provider, 'fxRate', new.fx_rate)),
      ('PLATFORM_FEE', new.id, new.seller_id, coalesce(new.service_fee_amount_usd, 0), 'USD',
       coalesce(new.service_fee_amount_usd, 0), '',
       jsonb_build_object('rate', new.service_fee_rate)),
      ('SUPPLIER_COST', new.id, new.seller_id,
       coalesce(new.supplier_subtotal_usd, 0) + coalesce(new.supplier_freight_usd, 0), 'USD',
       coalesce(new.supplier_subtotal_usd, 0) + coalesce(new.supplier_freight_usd, 0), '',
       jsonb_build_object('goods', new.supplier_subtotal_usd, 'freight', new.supplier_freight_usd)),
      ('SELLER_EARNING', new.id, new.seller_id, greatest(coalesce(new.seller_revenue_usd, 0), 0),
       'USD', greatest(coalesce(new.seller_revenue_usd, 0), 0), '', '{}'::jsonb)
    on conflict do nothing;
  end if;

  if coalesce(new.refunded_amount, 0) > coalesce(old.refunded_amount, 0) then
    insert into public.ledger_entries
      (entry_type, order_id, seller_id, amount, currency, reference, details)
    values
      ('REFUND', new.id, new.seller_id, new.refunded_amount - coalesce(old.refunded_amount, 0),
       coalesce(new.refund_currency, charge_currency), new.refunded_amount::text,
       coalesce(new.refunds -> -1, '{}'::jsonb))
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger ledger_orders
  after update on public.orders
  for each row execute function public.ledger_orders();

create or replace function public.ledger_billing()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    insert into public.ledger_entries
      (entry_type, billing_history_id, seller_id, amount, currency, amount_usd, reference, details)
    values
      ('SUBSCRIPTION_PAYMENT', new.id, new.seller_id, new.amount_kes, 'KES', new.amount_usd,
       coalesce(new.payment_reference, ''), jsonb_build_object('planId', new.plan_id))
    on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger ledger_billing
  after update on public.billing_history
  for each row execute function public.ledger_billing();

-- Both records are append-only for everyone, the service role and the
-- table owner included: a correction is a new row, never an edit.
create or replace function public.refuse_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = '42501';
end;
$$;

create trigger audit_logs_append_only
  before update or delete on public.audit_logs
  for each row execute function public.refuse_change();
create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function public.refuse_change();
create trigger ledger_entries_append_only
  before update or delete on public.ledger_entries
  for each row execute function public.refuse_change();
create trigger ledger_entries_no_truncate
  before truncate on public.ledger_entries
  for each statement execute function public.refuse_change();

-- ---------------------------------------------------------------------------
-- Webhook events (M5) — service role only
-- ---------------------------------------------------------------------------

-- Every IntaSend webhook that passes the challenge check, stored before it
-- is acted on, for reconciliation and disputes. Replays are harmless
-- anyway (re-verification plus CAS); the unique key keeps one row each.
create table public.webhook_events (
  id bigint generated always as identity primary key,
  provider text not null,
  invoice_id text not null,
  state text not null default '',
  api_ref text,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  outcome text,
  unique (provider, invoice_id, state)
);

alter table public.webhook_events enable row level security;

create policy "webhook_events: admin reads"
  on public.webhook_events for select
  using ((select public.is_admin()));

-- ---------------------------------------------------------------------------
-- Account deletion (L2)
-- ---------------------------------------------------------------------------

-- Called by the api function's deleteAccount route, which then soft-deletes
-- the Auth user. Orders, billing and ledger rows are financial records and
-- are kept, pointing at a scrubbed profile; personal data is removed.
-- Refused while the account has a paid order still in fulfilment.
create or replace function public.delete_account_data(p_uid uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prof public.profiles;
  open_orders integer;
  placeholder text := 'deleted-' || p_uid || '@deleted.invalid';
begin
  select * into prof from public.profiles where uid = p_uid for update;
  if not found then
    raise exception 'profile % not found', p_uid using errcode = 'P0002';
  end if;
  if prof.role = 'admin' then
    raise exception 'admin accounts are removed with grant-admin.js --revoke'
      using errcode = '42501';
  end if;

  select count(*) into open_orders
  from public.orders
  where (buyer_id = p_uid or seller_id = p_uid)
    and payment_status = 'paid'
    and status in ('pending', 'processing', 'shipped');
  if open_orders > 0 then
    return jsonb_build_object('deleted', false, 'reason', 'open_orders', 'openOrders', open_orders);
  end if;

  update public.profiles
  set name = 'Deleted user', email = placeholder, phone = null, photo_url = null,
      seller_status = case when role = 'seller' then 'suspended' else seller_status end
  where uid = p_uid;
  update public.store_customers
  set name = 'Deleted user', email = placeholder
  where uid = p_uid;
  -- A delivery address is personal data; the country stays for the books.
  update public.orders
  set shipping_address = jsonb_build_object(
        'countryCode', shipping_address -> 'countryCode', 'redacted', true)
  where buyer_id = p_uid;
  delete from public.notifications where recipient_id = p_uid;

  if prof.role = 'seller' then
    update public.products set is_listed = false where seller_id = p_uid;
    update public.stores set logo_url = null, banner_url = null where seller_id = p_uid;
    update public.subscriptions set status = 'cancelled', updated_at = now()
    where seller_id = p_uid;
  end if;

  perform public.write_audit('account.delete', 'profile', p_uid::text,
    jsonb_build_object('role', prof.role));
  return jsonb_build_object('deleted', true, 'role', prof.role);
end;
$$;

-- ---------------------------------------------------------------------------
-- Profile email follows Auth (L4)
-- ---------------------------------------------------------------------------

create or replace function public.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is not null and new.email is distinct from old.email then
    update public.profiles set email = lower(new.email) where uid = new.id;
    update public.store_customers set email = lower(new.email) where uid = new.id;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.sync_profile_email();

-- ---------------------------------------------------------------------------
-- Free-text length caps (L3)
-- ---------------------------------------------------------------------------

alter table public.notifications
  add constraint notifications_title_length check (char_length(title) <= 200) not valid,
  add constraint notifications_message_length check (char_length(message) <= 2000) not valid;

alter table public.profiles
  add constraint profiles_name_length check (char_length(name) <= 120) not valid,
  add constraint profiles_phone_length check (char_length(phone) <= 32) not valid,
  add constraint profiles_store_name_length check (char_length(store_name) <= 120) not valid;

alter table public.store_customers
  add constraint store_customers_name_length check (char_length(name) <= 120) not valid;

alter table public.stores
  add constraint stores_name_length check (char_length(name) <= 120) not valid,
  add constraint stores_tagline_length check (char_length(tagline) <= 280) not valid,
  add constraint stores_category_length check (char_length(category) <= 80) not valid,
  add constraint stores_color_length check (char_length(primary_color_hex) <= 16) not valid;

alter table public.products
  add constraint products_title_length check (char_length(title) <= 500) not valid,
  add constraint products_description_length check (char_length(description) <= 50000) not valid,
  add constraint products_category_length check (char_length(category) <= 120) not valid;

-- ---------------------------------------------------------------------------
-- Server-only functions, scheduled job, default grants (L5)
-- ---------------------------------------------------------------------------

revoke execute on function public.seller_order_gate(uuid) from public, anon, authenticated;
revoke execute on function public.expire_unpaid_orders() from public, anon, authenticated;
revoke execute on function public.delete_account_data(uuid) from public, anon, authenticated;
revoke execute on function public.write_audit(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.seller_order_gate(uuid) to service_role;
grant execute on function public.expire_unpaid_orders() to service_role;
grant execute on function public.delete_account_data(uuid) to service_role;
grant execute on function public.write_audit(text, text, text, jsonb) to service_role;

-- The backend-only tables above: clients get nothing but what their
-- select policies allow (Supabase's default privileges grant them all).
revoke insert, update, delete on public.audit_logs, public.ledger_entries, public.webhook_events
  from anon, authenticated;
revoke update, delete on public.audit_logs, public.ledger_entries from service_role;

-- L5: PostgREST can't issue these, but Supabase's default privileges grant
-- them; nothing needs them.
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed: order expiry sweep not scheduled';
    return;
  end if;
  -- Every 15 minutes: cancels unpaid orders past expires_at (M7).
  perform cron.schedule('sellora-expire-orders', '*/15 * * * *',
    $job$ select public.expire_unpaid_orders() $job$);
end;
$$;
