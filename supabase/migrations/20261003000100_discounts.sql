-- Discount codes (implementation plan PHASE 9, TODO.md §27).
--
-- A seller creates codes for their own store; a buyer types one at
-- checkout. The api function's createOrder is the only place a discount is
-- priced (supabase/functions/_shared/discounts.js): the seller absorbs it,
-- the 7% service fee is taken on what the buyer actually pays, and a code
-- that would push the order below CJ's cost is refused. The trigger at the
-- end enforces usage limits when the order row is written, so two buyers
-- racing for a code's last use can't both get it.
--
-- Amounts are in the listings' currency, which is USD today (see the
-- retailUnitPriceUsd note in createOrder).
--
-- Not here, deliberately: free-shipping codes (CJ freight still has to be
-- paid, and who pays it is an owner call), collections and customer groups
-- (neither model exists yet), automatic (code-less) discounts.

create table public.discounts (
  id text primary key default gen_random_uuid()::text,
  store_id text not null references public.stores (id),
  -- Stored upper-case; buyers' input is normalized the same way.
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{2,31}$'),
  kind text not null check (kind in ('percentage', 'fixed_amount')),
  value numeric(12, 2) not null check (value > 0),
  min_subtotal numeric(12, 2) not null default 0 check (min_subtotal >= 0),
  -- Empty means every product in the store.
  product_ids text[] not null default '{}'
    check (cardinality(product_ids) <= 200),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  usage_limit integer check (usage_limit is null or usage_limit > 0),
  once_per_customer boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (store_id, code),
  check (kind <> 'percentage' or value <= 100),
  check (ends_at is null or ends_at > starts_at)
);

alter table public.discounts enable row level security;

-- A store's codes are its owner's business: buyers never list them, they
-- can only test one they already know (storefront_discount below).
create policy "discounts: owner or admin reads"
  on public.discounts for select
  using (public.owns_store(store_id) or (select public.is_admin()));

create policy "discounts: owner creates"
  on public.discounts for insert
  with check (public.owns_store(store_id));

create policy "discounts: owner updates"
  on public.discounts for update
  using (public.owns_store(store_id))
  with check (public.owns_store(store_id));

-- A code an order already used can't be deleted (the orders foreign key
-- below refuses it); the seller deactivates it instead.
create policy "discounts: owner deletes"
  on public.discounts for delete
  using (public.owns_store(store_id));

create or replace function public.discounts_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_privileged() then
    return new;
  end if;
  if new.id is distinct from old.id
     or new.store_id is distinct from old.store_id
     or new.created_at is distinct from old.created_at then
    raise exception 'discount id, store and created_at are immutable' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger discounts_guard_update
  before update on public.discounts
  for each row execute function public.discounts_guard_update();

-- ---------------------------------------------------------------------------
-- Orders carry the code they used
-- ---------------------------------------------------------------------------

alter table public.orders
  add column discount_id text references public.discounts (id),
  -- Snapshot of the code as typed, and what it took off, in the order's
  -- own currency (like `total`). Visible to the buyer on their receipt.
  add column discount_code text,
  add column discount_amount numeric(12, 2) not null default 0,
  -- Server-only, parallel to the other *_usd bookkeeping columns.
  add column discount_amount_usd numeric(12, 2) not null default 0;

create index orders_discount_idx on public.orders (discount_id, buyer_id)
  where discount_id is not null;

grant select (discount_code, discount_amount) on public.orders to authenticated;

-- Same view as 20260928000000_security_hardening.sql, plus the discount
-- columns (appended, as `create or replace view` requires).
create or replace view public.seller_orders with (security_barrier = true) as
select
  o.id, o.code, o.buyer_id, o.seller_id, o.store_id, o.items, o.status,
  o.total, o.currency, o.shipping_address, o.payment_method,
  o.payment_reference, o.tracking_number, o.payment_status,
  o.service_fee_rate, o.service_fee_amount, o.seller_revenue, o.payment_fee,
  o.shipping_fee, o.logistic_name, o.created_at, o.updated_at,
  o.payment_provider, o.tracking, o.refunded_amount,
  o.discount_id, o.discount_code, o.discount_amount
from public.orders o
where o.seller_id = (select auth.uid())
   or public.owns_store(o.store_id)
   or (select public.is_admin());

-- An order counts against a code's limits until it's cancelled: an unpaid
-- order that expires (expire_unpaid_orders) gives its use back.
create or replace function public.discount_uses(p_discount_id text, p_buyer_id uuid default null)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.orders
  where discount_id = p_discount_id
    and status <> 'cancelled'
    and (p_buyer_id is null or buyer_id = p_buyer_id)
$$;

revoke execute on function public.discount_uses(text, uuid) from public, anon, authenticated;

-- The last word on a code's limits, at the moment the order is written.
-- The row lock serializes concurrent checkouts on the same code.
create or replace function public.orders_enforce_discount()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.discounts;
begin
  if new.discount_id is null then
    return new;
  end if;
  select * into d from public.discounts where id = new.discount_id for update;
  if not found
     or d.store_id is distinct from new.store_id
     or not d.is_active
     or d.starts_at > now()
     or (d.ends_at is not null and d.ends_at <= now()) then
    raise exception 'discount_unavailable' using errcode = 'P0001';
  end if;
  if d.usage_limit is not null
     and public.discount_uses(d.id) >= d.usage_limit then
    raise exception 'discount_exhausted' using errcode = 'P0001';
  end if;
  if d.once_per_customer
     and public.discount_uses(d.id, new.buyer_id) > 0 then
    raise exception 'discount_already_used' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger orders_enforce_discount
  before insert on public.orders
  for each row execute function public.orders_enforce_discount();

revoke execute on function public.orders_enforce_discount() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Client reads
-- ---------------------------------------------------------------------------

-- What checkout shows when a buyer applies a code: its terms, if it's
-- usable right now, else null. Only someone who already knows the code can
-- ask, and the answer has no usage figures. createOrder re-checks all of
-- it; this is a preview.
create or replace function public.storefront_discount(p_store_id text, p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'code', d.code,
    'kind', d.kind,
    'value', d.value,
    'minSubtotal', d.min_subtotal,
    'productIds', to_jsonb(d.product_ids),
    'endsAt', d.ends_at,
    'oncePerCustomer', d.once_per_customer)
  from public.discounts d
  join public.stores s on s.id = d.store_id
  where d.store_id = p_store_id
    and d.code = upper(btrim(coalesce(p_code, '')))
    and d.is_active
    and d.starts_at <= now()
    and (d.ends_at is null or d.ends_at > now())
    and public.seller_can_sell(s.seller_id)
    and (d.usage_limit is null or public.discount_uses(d.id) < d.usage_limit)
$$;

revoke execute on function public.storefront_discount(text, text) from public;
grant execute on function public.storefront_discount(text, text) to anon, authenticated;

-- How many live orders used each of a store's codes, for the seller's
-- Discounts screen. Owner or admin only.
create or replace function public.store_discount_usage(p_store_id text)
returns table (discount_id text, uses integer)
language sql
stable
security definer
set search_path = ''
as $$
  select d.id, public.discount_uses(d.id)
  from public.discounts d
  where d.store_id = p_store_id
    and (public.owns_store(p_store_id) or (select public.is_admin()))
$$;

revoke execute on function public.store_discount_usage(text) from public, anon;
grant execute on function public.store_discount_usage(text) to authenticated;
