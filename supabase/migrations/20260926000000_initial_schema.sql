-- Sellora on Supabase — Phase 1 schema (identity + app data).
--
-- Replaces firestore.rules / firestore.indexes.json. Every rule that file
-- enforced is carried over here as an RLS policy, a column-level grant, or
-- a guard trigger; the comments name which old rule each one replaces.
-- See WORKLOG.md, 2026-09-26.
--
-- Naming: columns are snake_case. The Flutter models keep their camelCase
-- fromMap/toMap keys, and SupabaseService.toRow/fromRow translate the top
-- level (lib/data/services/supabase_service.dart). jsonb columns (items,
-- shipping_address, variants, features, rates) keep camelCase inside,
-- untranslated.
--
-- Not here yet, deliberately: the tables only the Cloud Functions touch
-- (the shared CJ catalog, rate_limits, refunds/fulfilment bookkeeping on
-- orders). They arrive with Phase 2, when functions/ is ported to Edge
-- Functions, so their shape comes from the code that writes them.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Admin access comes from app_metadata.role only, which only the service
-- role can set (supabase/scripts/grant-admin.js). Replaces the Firebase
-- `admin` custom claim; the `role: 'admin'` profile column is for app
-- routing, never for access — same split as before.
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false)
$$;

-- True for the service role, the SQL editor, and security-definer triggers
-- — anything that isn't a client request. Guard triggers let these through,
-- the way the Firebase Admin SDK bypassed firestore.rules.
create or replace function public.is_privileged()
returns boolean
language sql
stable
set search_path = ''
as $$
  select current_user not in ('authenticated', 'anon')
$$;

-- Mirrors lib/core/utils/slug.dart's slugify() exactly (including the
-- 60-character cap that leaves room for a `-N` suffix).
create or replace function public.slugify(input text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  s text := lower(btrim(coalesce(input, '')));
begin
  s := regexp_replace(s, '[''’]', '', 'g');
  s := regexp_replace(s, '[^a-z0-9]+', '-', 'g');
  s := regexp_replace(s, '^-+|-+$', '', 'g');
  if s = '' then
    return 'store';
  end if;
  if char_length(s) > 60 then
    s := regexp_replace(left(s, 60), '-+$', '');
  end if;
  return s;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles (was users/{uid})
-- ---------------------------------------------------------------------------

create table public.profiles (
  uid uuid primary key references auth.users (id) on delete cascade,
  name text not null default '',
  email text not null,
  role text not null check (role in ('buyer', 'seller', 'admin')),
  phone text,
  photo_url text,
  seller_status text check (seller_status in ('pendingApproval', 'active', 'suspended')),
  store_name text,
  subscription_plan_id text,
  subscription_active_until timestamptz,
  seller_terms_accepted_at timestamptz,
  seller_terms_version text,
  currency_code text not null default 'USD',
  -- Buyer-only: the one store they're a customer of. FK added below, once
  -- `stores` exists.
  store_id text,
  created_at timestamptz not null default now()
);

create index profiles_role_idx on public.profiles (role);

alter table public.profiles enable row level security;

create policy "profiles: read own, admin reads all"
  on public.profiles for select
  using (uid = (select auth.uid()) or (select public.is_admin()));

-- No insert policy: profiles are created only by handle_new_user() below,
-- in the same transaction as the auth.users row. That closes the hole the
-- old `users` create rule had to police field-by-field (a client minting
-- its own role: admin or an already-active subscription), and it means a
-- failed profile write can no longer strand an Auth account.

create policy "profiles: update own, admin updates any"
  on public.profiles for update
  using (uid = (select auth.uid()) or (select public.is_admin()))
  with check (uid = (select auth.uid()) or (select public.is_admin()));

-- Replaces the `users` update rule's touchesAny() list. A user may never
-- change their own role, subscription state, approval status, terms record
-- or store; an admin may edit anyone but may not mint another admin.
create or replace function public.profiles_guard_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if public.is_privileged() then
    return new;
  end if;
  if new.uid is distinct from old.uid
     or new.email is distinct from old.email
     or new.created_at is distinct from old.created_at then
    raise exception 'profile identity fields are immutable' using errcode = '42501';
  end if;
  if (select public.is_admin()) then
    if new.role is distinct from old.role and new.role = 'admin' then
      raise exception 'admin is provisioned server-side only' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.role is distinct from old.role
     or new.subscription_plan_id is distinct from old.subscription_plan_id
     or new.subscription_active_until is distinct from old.subscription_active_until
     or new.seller_status is distinct from old.seller_status
     or new.seller_terms_accepted_at is distinct from old.seller_terms_accepted_at
     or new.seller_terms_version is distinct from old.seller_terms_version
     or new.store_id is distinct from old.store_id then
    raise exception 'field is server-owned' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_update
  before update on public.profiles
  for each row execute function public.profiles_guard_update();

-- ---------------------------------------------------------------------------
-- stores (was stores/{storeId} + store_slugs/{slug})
-- ---------------------------------------------------------------------------

create table public.stores (
  id text primary key,
  -- The unique constraint replaces the store_slugs reservation collection:
  -- two sellers racing for one slug now simply get a unique violation.
  slug text not null unique
    check (char_length(slug) <= 80 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  seller_id uuid not null references public.profiles (uid),
  name text not null,
  tagline text,
  -- Still inline data: URIs today (see lib/core/utils/image_data_url.dart).
  logo_url text,
  banner_url text,
  primary_color_hex text,
  category text,
  country_code text,
  currency_code text not null default 'KES',
  shipping_zones text[] not null default array['kenya', 'us', 'uk', 'eu'],
  created_at timestamptz not null default now()
);

create index stores_seller_id_idx on public.stores (seller_id);

alter table public.profiles
  add constraint profiles_store_id_fkey
  foreign key (store_id) references public.stores (id);

create index profiles_store_id_idx on public.profiles (store_id);

alter table public.stores enable row level security;

-- Public, like before: a prospective buyer browses a store before they
-- have an account.
create policy "stores: public read"
  on public.stores for select
  using (true);

-- The onboarding "create your store" recovery path (createStoreForSeller in
-- lib/data/repositories/store_repository.dart). Sign-up itself creates the
-- store in handle_new_user().
create policy "stores: sellers create their own"
  on public.stores for insert
  with check (
    seller_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.uid = (select auth.uid()) and p.role = 'seller'
    )
  );

create policy "stores: owner or admin updates"
  on public.stores for update
  using (seller_id = (select auth.uid()) or (select public.is_admin()))
  with check (seller_id = (select auth.uid()) or (select public.is_admin()));

-- The slug is a public address and the owner is the tenant boundary:
-- neither may move, or one seller could serve a look-alike storefront at
-- another's URL.
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
  return new;
end;
$$;

create trigger stores_guard_update
  before update on public.stores
  for each row execute function public.stores_guard_update();

create or replace function public.owns_store(target_store_id text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from public.stores s
    where s.id = target_store_id and s.seller_id = (select auth.uid())
  )
$$;

-- ---------------------------------------------------------------------------
-- store_customers (was stores/{storeId}/customers/{uid})
-- ---------------------------------------------------------------------------

-- Its own table rather than a column read off `profiles`, so a seller can
-- be granted their own store's customers without any read on `profiles`.
create table public.store_customers (
  store_id text not null references public.stores (id),
  uid uuid not null references public.profiles (uid) on delete cascade,
  name text not null default '',
  email text not null,
  created_at timestamptz not null default now(),
  primary key (store_id, uid)
);

create index store_customers_uid_idx on public.store_customers (uid);

alter table public.store_customers enable row level security;

create policy "store_customers: self, store owner, admin read"
  on public.store_customers for select
  using (uid = (select auth.uid()) or public.owns_store(store_id) or (select public.is_admin()));

-- Rows are created by handle_new_user() only.

-- ---------------------------------------------------------------------------
-- products (was stores/{storeId}/products/{productId})
-- ---------------------------------------------------------------------------

-- `id` is the CJ catalog product id, so it's only unique within a store.
-- The shared CJ catalog (Firestore's top-level `products`) becomes
-- `catalog_products` in Phase 2.
create table public.products (
  store_id text not null references public.stores (id),
  id text not null,
  seller_id uuid not null references public.profiles (uid),
  cj_product_id text,
  title text not null default '',
  image_url text,
  images text[] not null default '{}',
  cost_price numeric(12, 2) not null default 0,
  sell_price numeric(12, 2) not null default 0,
  compare_at_price numeric(12, 2),
  currency text,
  category text,
  description text,
  variants jsonb not null default '[]',
  is_listed boolean not null default false,
  sold_count integer not null default 0,
  rating numeric not null default 0,
  stock integer not null default 0,
  discount_percent integer,
  created_at timestamptz not null default now(),
  primary key (store_id, id)
);

create index products_seller_id_idx on public.products (seller_id);
create index products_id_idx on public.products (id);
create index products_listed_category_idx on public.products (is_listed, category);

alter table public.products enable row level security;

-- Listed products are public; a draft (is_listed false) is the owner's
-- alone, so its cost price and unfinished copy don't leak.
create policy "products: listed public, drafts owner-only"
  on public.products for select
  using (is_listed or public.owns_store(store_id) or (select public.is_admin()));

-- Checked against the store's own owner, not a bare role, so one seller
-- can't write into another's store (same as the old per-store rule).
create policy "products: store owner creates"
  on public.products for insert
  with check (seller_id = (select auth.uid()) and public.owns_store(store_id));

create policy "products: store owner updates"
  on public.products for update
  using (public.owns_store(store_id))
  with check (seller_id = (select auth.uid()) and public.owns_store(store_id));

-- ---------------------------------------------------------------------------
-- orders (was flat orders/{id} AND stores/{storeId}/orders/{id})
-- ---------------------------------------------------------------------------

-- One table. The Firestore split existed so a missed `.where()` couldn't
-- leak across tenants; RLS gives that guarantee on a single table.
--
-- Phase 2 (porting functions/lib/orders.js) will add the server-only
-- columns createOrder/refundOrder/fulfilment write (cj_order_id, refunds,
-- fulfilment attempts, fx_rate, ...).
create table public.orders (
  id text primary key default gen_random_uuid()::text,
  code text not null,
  buyer_id uuid not null references public.profiles (uid),
  seller_id uuid not null references public.profiles (uid),
  store_id text references public.stores (id),
  items jsonb not null default '[]',
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'shipped', 'delivered', 'cancelled')),
  total numeric(12, 2) not null default 0,
  currency text not null default 'USD',
  shipping_address jsonb not null default '{}',
  payment_method text,
  payment_reference text,
  tracking_number text,
  payment_status text not null default 'pending'
    check (payment_status in ('pending', 'paid', 'failed')),
  service_fee_rate numeric not null default 0,
  service_fee_amount numeric(12, 2) not null default 0,
  seller_revenue numeric(12, 2) not null default 0,
  payment_fee numeric(12, 2) not null default 0,
  shipping_fee numeric(12, 2) not null default 0,
  logistic_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create index orders_buyer_idx on public.orders (buyer_id, created_at desc);
create index orders_seller_idx on public.orders (seller_id, created_at desc);
create index orders_store_idx on public.orders (store_id, created_at desc);

alter table public.orders enable row level security;

create policy "orders: buyer, seller, store owner, admin read"
  on public.orders for select
  using (
    buyer_id = (select auth.uid())
    or seller_id = (select auth.uid())
    or public.owns_store(store_id)
    or (select public.is_admin())
  );

-- No insert policy: orders are created server-side only (createOrder
-- re-prices from CJ), so a client can't write a self-reported total.

create policy "orders: seller or admin updates"
  on public.orders for update
  using (seller_id = (select auth.uid()) or public.owns_store(store_id) or (select public.is_admin()))
  with check (seller_id = (select auth.uid()) or public.owns_store(store_id) or (select public.is_admin()));

-- Replaces serverOwnedOrderFields(): clients can change fulfilment status
-- and nothing else — not ownership, money, or payment state. Refunds and
-- payment corrections stay server-side, where they leave an audit trail.
revoke update on public.orders from anon, authenticated;
grant update (status, updated_at) on public.orders to authenticated;

-- ---------------------------------------------------------------------------
-- notifications (was users/{uid}/notifications/{id})
-- ---------------------------------------------------------------------------

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (uid) on delete cascade,
  title text not null,
  message text not null,
  order_id text references public.orders (id),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index notifications_recipient_idx
  on public.notifications (recipient_id, created_at desc);
create index notifications_order_id_idx on public.notifications (order_id);

alter table public.notifications enable row level security;

create policy "notifications: recipient reads"
  on public.notifications for select
  using (recipient_id = (select auth.uid()));

-- A user may write to their own inbox, or alert the other party of an
-- order they're both on — the order itself proves the relationship.
create policy "notifications: self or order counterparty creates"
  on public.notifications for insert
  with check (
    recipient_id = (select auth.uid())
    or exists (
      select 1 from public.orders o
      where o.id = order_id
        and (
          (o.buyer_id = (select auth.uid()) and o.seller_id = recipient_id)
          or (o.seller_id = (select auth.uid()) and o.buyer_id = recipient_id)
        )
    )
  );

create policy "notifications: recipient marks read"
  on public.notifications for update
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

revoke update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

-- NotificationRepository.watchForUser streams this table.
alter publication supabase_realtime add table public.notifications;

-- ---------------------------------------------------------------------------
-- Subscriptions & billing
-- ---------------------------------------------------------------------------

create table public.subscription_plans (
  id text primary key,
  name text not null,
  price_usd numeric(12, 2) not null default 0,
  price_kes numeric(12, 2) not null default 0,
  billing_period_days integer not null default 30,
  listing_limit integer not null default 25,
  commission_percent numeric not null default 5,
  perks text[] not null default '{}',
  is_popular boolean not null default false,
  order_limit integer not null default -1,
  store_limit integer not null default 1,
  features jsonb not null default '{}'
);

alter table public.subscription_plans enable row level security;

create policy "subscription_plans: public read"
  on public.subscription_plans for select
  using (true);

-- Per-command rather than `for all`, which would add a second permissive
-- SELECT policy alongside public read.
create policy "subscription_plans: admin inserts"
  on public.subscription_plans for insert
  with check ((select public.is_admin()));

create policy "subscription_plans: admin updates"
  on public.subscription_plans for update
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "subscription_plans: admin deletes"
  on public.subscription_plans for delete
  using ((select public.is_admin()));

-- Server-written only (subscribeSeller / the IntaSend webhook).
create table public.billing_history (
  id text primary key default gen_random_uuid()::text,
  seller_id uuid not null references public.profiles (uid),
  plan_id text not null references public.subscription_plans (id),
  plan_name text not null default '',
  amount_kes numeric(12, 2) not null default 0,
  amount_usd numeric(12, 2) not null default 0,
  billing_period_days integer not null default 30,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  payment_provider text not null default 'INTASEND',
  payment_reference text,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create index billing_history_seller_idx on public.billing_history (seller_id, created_at desc);
create index billing_history_plan_id_idx on public.billing_history (plan_id);

alter table public.billing_history enable row level security;

create policy "billing_history: seller or admin reads"
  on public.billing_history for select
  using (seller_id = (select auth.uid()) or (select public.is_admin()));

-- One row per seller, upserted only on payment confirmation. Never
-- client-writable: an order-limit check will read it.
create table public.subscriptions (
  seller_id uuid primary key references public.profiles (uid),
  plan_id text not null references public.subscription_plans (id),
  status text not null default 'active',
  order_limit integer not null default -1,
  current_period_start timestamptz not null,
  current_period_end timestamptz not null,
  last_billing_history_id text references public.billing_history (id),
  updated_at timestamptz
);

create index subscriptions_plan_id_idx on public.subscriptions (plan_id);
create index subscriptions_last_billing_history_id_idx
  on public.subscriptions (last_billing_history_id);

alter table public.subscriptions enable row level security;

create policy "subscriptions: seller or admin reads"
  on public.subscriptions for select
  using (seller_id = (select auth.uid()) or (select public.is_admin()));

-- ---------------------------------------------------------------------------
-- fx_rates (was config/fx)
-- ---------------------------------------------------------------------------

-- A single row, refreshed daily server-side. Public market data: the app
-- reads it only to display converted estimates; orders are priced from the
-- server's own read.
create table public.fx_rates (
  id text primary key default 'current' check (id = 'current'),
  base text not null default 'USD',
  rates jsonb not null default '{}',
  fetched_at timestamptz
);

alter table public.fx_rates enable row level security;

create policy "fx_rates: public read"
  on public.fx_rates for select
  using (true);

-- ---------------------------------------------------------------------------
-- Sign-up: profile (+ store, + store membership) in the same transaction
-- ---------------------------------------------------------------------------

-- The app's signUp() passes user metadata:
--   buyer:  {role: 'buyer',  name, store_id}
--   seller: {role: 'seller', name, phone, store_name, seller_terms_version}
-- User metadata is client-controlled, so only what those two sign-ups may
-- legitimately produce is accepted: a buyer, or a seller pending approval
-- with no subscription. Anything else raises and the auth.users insert
-- rolls back with it.
--
-- Admins are the exception: grant-admin.js creates them with
-- app_metadata.role = 'admin', which only the service role can set.
--
-- An account created some other way (for example from the dashboard) gets
-- no profile, and the app refuses it at sign-in ('profile-missing').
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := meta ->> 'role';
  display_name text := btrim(coalesce(meta ->> 'name', ''));
  base_slug text;
  candidate text;
  suffix integer := 2;
begin
  if coalesce(new.raw_app_meta_data ->> 'role', '') = 'admin' then
    insert into public.profiles (uid, name, email, role)
    values (new.id, coalesce(nullif(display_name, ''), 'Sellora Admin'),
            lower(new.email), 'admin');
    return new;
  end if;

  if requested_role is null then
    return new;
  end if;

  if requested_role = 'buyer' then
    if not exists (select 1 from public.stores where id = meta ->> 'store_id') then
      raise exception 'unknown store' using errcode = '23503';
    end if;
    insert into public.profiles (uid, name, email, role, store_id)
    values (new.id, display_name, lower(new.email), 'buyer', meta ->> 'store_id');
    insert into public.store_customers (store_id, uid, name, email)
    values (meta ->> 'store_id', new.id, display_name, lower(new.email));
    return new;
  end if;

  if requested_role = 'seller' then
    -- Keep in step with sellerTermsVersion in lib/data/models/user_model.dart.
    if coalesce(meta ->> 'seller_terms_version', '') <> '2026-09-17' then
      raise exception 'seller terms not accepted' using errcode = '42501';
    end if;
    if btrim(coalesce(meta ->> 'store_name', '')) = '' then
      raise exception 'store name required' using errcode = '23502';
    end if;

    insert into public.profiles (
      uid, name, email, role, phone, store_name, seller_status,
      seller_terms_accepted_at, seller_terms_version)
    values (
      new.id, display_name, lower(new.email), 'seller',
      nullif(btrim(coalesce(meta ->> 'phone', '')), ''),
      btrim(meta ->> 'store_name'), 'pendingApproval',
      now(), meta ->> 'seller_terms_version');

    -- Same first-free-slug rule as createStoreForSeller in Dart
    -- (`my-shop`, `my-shop-2`, ...), and the same `store-{uid}` id.
    base_slug := public.slugify(meta ->> 'store_name');
    candidate := base_slug;
    while exists (select 1 from public.stores where slug = candidate) loop
      candidate := base_slug || '-' || suffix;
      suffix := suffix + 1;
    end loop;

    insert into public.stores (id, slug, seller_id, name)
    values ('store-' || new.id, candidate, new.id, btrim(meta ->> 'store_name'));
    return new;
  end if;

  raise exception 'role % cannot be self-assigned', requested_role using errcode = '42501';
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- grant-admin.js --revoke: ends every session so a revoked admin's refresh
-- token stops working (the access token still lives out its expiry, as
-- with Firebase's revokeRefreshTokens).
create or replace function public.revoke_user_sessions(target_uid uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.sessions where user_id = target_uid;
$$;

revoke execute on function public.revoke_user_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_user_sessions(uuid) to service_role;
