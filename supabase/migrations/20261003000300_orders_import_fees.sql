-- TODO.md §13-15: the import editor's listing fields, the seller's order
-- detail (timeline, notes, cancellation, CJ fulfilment state), and an
-- admin-configurable service fee that every order snapshots.
-- See WORKLOG.md, 2026-10-03.

-- ---------------------------------------------------------------------------
-- §15: the service fee is an admin setting, snapshotted per order
-- ---------------------------------------------------------------------------

-- `fees` = {"serviceFeeRate": 0.07, "chargeOnShipping": false}. Read only
-- through service_fee_settings() below, which supplies the defaults.
alter table public.app_config drop constraint app_config_key_check;
alter table public.app_config add constraint app_config_key_check
  check (key in ('pricing', 'catalog', 'fees'));

-- 0-30%, and the shipping switch is a real boolean when present. Mirrors
-- MAX_SERVICE_FEE_RATE in supabase/functions/_shared/fees.js.
alter table public.app_config add constraint app_config_fees_valid check (
  case when key = 'fees' then
    jsonb_typeof(value) = 'object'
    and jsonb_typeof(value -> 'serviceFeeRate') = 'number'
    and case when jsonb_typeof(value -> 'serviceFeeRate') = 'number'
             then (value ->> 'serviceFeeRate')::numeric between 0 and 0.3
             else false end
    and coalesce(jsonb_typeof(value -> 'chargeOnShipping'), 'boolean') = 'boolean'
  else true end);

-- What createOrder charges (fees.js) and the import screen prices against.
-- app_config itself stays admin-only: the other rows hold pricing margins.
create or replace function public.service_fee_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'serviceFeeRate', coalesce((value ->> 'serviceFeeRate')::numeric, 0.07),
    'chargeOnShipping', coalesce((value ->> 'chargeOnShipping')::boolean, false))
  from (select (select value from public.app_config where key = 'fees') as value) s
$$;

revoke execute on function public.service_fee_settings() from public, anon;
grant execute on function public.service_fee_settings() to authenticated, service_role;

-- A fee change is a platform-wide money decision: keep who made it and when.
create or replace function public.audit_app_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.write_audit('config.' || lower(tg_op), 'app_config',
    coalesce(new.key, old.key),
    jsonb_build_object('old', case when tg_op = 'INSERT' then null else old.value end,
                       'new', case when tg_op = 'DELETE' then null else new.value end));
  return coalesce(new, old);
end;
$$;

create trigger audit_app_config
  after insert or update or delete on public.app_config
  for each row execute function public.audit_app_config();

-- What the fee was charged on, next to the existing service_fee_rate
-- snapshot. Orders from before this column were all goods-only.
alter table public.orders
  add column service_fee_base text not null default 'subtotal'
    check (service_fee_base in ('subtotal', 'subtotal_and_shipping'));

grant select (service_fee_base) on public.orders to authenticated;

-- ---------------------------------------------------------------------------
-- §14: seller order management
-- ---------------------------------------------------------------------------

-- A seller may now cancel an order nobody has paid for, as an admin already
-- could. One with a payment in flight (awaiting_confirmation) can't be: if
-- that payment lands, fulfillOrder parks the paid-but-cancelled order for a
-- refund, which is the admin's to resolve. Otherwise unchanged from
-- 20260928000000_security_hardening.sql.
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
  if new.status = 'cancelled'
     and old.status = 'pending'
     and old.payment_status in ('pending', 'failed')
     and ((select public.is_admin())
          or old.seller_id = (select auth.uid())
          or public.owns_store(old.store_id)) then
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

-- The audit trail doubles as the order timeline, so it now also records the
-- tracking number arriving. Otherwise the same as the hardening migration.
create or replace function public.audit_orders()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changes jsonb := public.jsonb_changes(to_jsonb(old), to_jsonb(new), array[
    'status', 'payment_status', 'refund_status', 'refunded_amount',
    'cj_order_status', 'tracking_number']);
begin
  if changes <> '{}'::jsonb then
    perform public.write_audit('order.update', 'order', new.id,
      jsonb_build_object('changes', changes));
  end if;
  return new;
end;
$$;

-- Internal notes on an order: the seller's and Sellora staff's, never the
-- buyer's. Append-only, like the rest of the timeline they sit in.
create table public.order_notes (
  id bigint generated always as identity primary key,
  order_id text not null references public.orders (id),
  author_id uuid not null,
  author_role text not null,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index order_notes_order_idx on public.order_notes (order_id, created_at);

alter table public.order_notes enable row level security;

create or replace function public.can_manage_order(p_order_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and (o.seller_id = (select auth.uid())
           or public.owns_store(o.store_id)
           or (select public.is_admin())))
$$;

revoke execute on function public.can_manage_order(text) from public, anon;
grant execute on function public.can_manage_order(text) to authenticated;

create policy "order_notes: seller and admin read"
  on public.order_notes for select
  using (public.can_manage_order(order_id));

create policy "order_notes: seller and admin add"
  on public.order_notes for insert
  with check (public.can_manage_order(order_id));

-- The author and time are the server's, whatever the client sent.
create or replace function public.order_notes_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.author_id := auth.uid();
  new.author_role := case when public.is_admin() then 'admin' else 'seller' end;
  new.created_at := now();
  new.body := btrim(new.body);
  if new.author_id is null then
    raise exception 'a note needs a signed-in author' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger order_notes_stamp
  before insert on public.order_notes
  for each row execute function public.order_notes_stamp();

create trigger order_notes_append_only
  before update or delete on public.order_notes
  for each row execute function public.refuse_change();

revoke update, delete, truncate on public.order_notes from anon, authenticated;
revoke all on public.order_notes from anon;

-- One order's history, oldest first: its creation, every audited change to
-- its payment, fulfilment, CJ and refund state, and its notes. Only for
-- whoever may manage the order; anyone else gets no rows.
create or replace function public.order_timeline(p_order_id text)
returns table (occurred_at timestamptz, kind text, actor_role text, details jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  with o as (
    select id, created_at, total, currency from public.orders
    where id = p_order_id and public.can_manage_order(p_order_id)
  )
  select * from (
    select o.created_at, 'created'::text, 'buyer'::text,
           jsonb_build_object('total', o.total, 'currency', o.currency)
    from o
    union all
    select a.occurred_at, 'change', a.actor_role, coalesce(a.details -> 'changes', '{}'::jsonb)
    from public.audit_logs a join o on a.entity_id = o.id
    where a.entity_type = 'order' and a.action = 'order.update'
    union all
    select n.created_at, 'note', n.author_role, jsonb_build_object('body', n.body)
    from public.order_notes n join o on n.order_id = o.id
  ) t (occurred_at, kind, actor_role, details)
  order by occurred_at, kind
$$;

revoke execute on function public.order_timeline(text) from public, anon;
grant execute on function public.order_timeline(text) to authenticated;

-- The seller's order view gains the fee base and CJ's side of fulfilment:
-- whether the order reached CJ, and CJ's order number for support. CJ's
-- error text stays server-only. Same columns as
-- 20261003000100_discounts.sql's view, plus these, appended.
create or replace view public.seller_orders with (security_barrier = true) as
select
  o.id, o.code, o.buyer_id, o.seller_id, o.store_id, o.items, o.status,
  o.total, o.currency, o.shipping_address, o.payment_method,
  o.payment_reference, o.tracking_number, o.payment_status,
  o.service_fee_rate, o.service_fee_amount, o.seller_revenue, o.payment_fee,
  o.shipping_fee, o.logistic_name, o.created_at, o.updated_at,
  o.payment_provider, o.tracking, o.refunded_amount,
  o.discount_id, o.discount_code, o.discount_amount,
  o.service_fee_base, o.cj_order_status, o.cj_order_number
from public.orders o
where o.seller_id = (select auth.uid())
   or public.owns_store(o.store_id)
   or (select public.is_admin());

-- ---------------------------------------------------------------------------
-- §13: listing fields the import editor sets
-- ---------------------------------------------------------------------------

-- At most 20 tags of 1-40 characters each.
create or replace function public.valid_tags(tags text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(cardinality(tags), 0) <= 20
     and not exists (select 1 from unnest(tags) t where char_length(t) not between 1 and 40)
$$;

alter table public.products
  add column tags text[] not null default '{}' check (public.valid_tags(tags)),
  add column seo_title text check (char_length(seo_title) <= 120),
  add column seo_description text check (char_length(seo_description) <= 320);

-- Same view as 20261003000200_admin_platform.sql, plus the three new
-- columns, appended.
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
  p.created_at,
  p.tags, p.seo_title, p.seo_description
from public.products p
where p.is_listed
  and public.seller_can_sell(p.seller_id)
  and not exists (
    select 1 from public.stores s where s.id = p.store_id and s.is_suspended);

revoke all on public.storefront_products from public, anon, authenticated;
grant select on public.storefront_products to anon, authenticated;
