-- Catalog (implementation plan PHASE 4): product synchronization. A seller's
-- listing is a snapshot of CJ at import time; CJ's cost moves and products
-- disappear. The syncListings job (supabase/functions/_shared/listingSync.js)
-- re-reads CJ for listed products, oldest-checked first, refreshes the
-- listing's cost, and flags one checkout would refuse. It never unlists:
-- that stays the seller's call, and checkout already refuses the sale.
-- See SELLORA_SECURITY_AUDIT.md §7.

alter table public.products
  add column supplier_checked_at timestamptz,
  add column supplier_alert text
    check (supplier_alert in ('below_cost', 'unavailable'));

comment on column public.products.supplier_alert is
  'Set by syncListings: below_cost (the price less the fee no longer covers CJ''s cost) or unavailable (CJ returned none of its enabled variants). Server-owned.';

-- The job's queue: listed products, never-checked first.
create index products_supplier_checked_idx
  on public.products (supplier_checked_at nulls first)
  where is_listed;

-- Replaces 20260928000000_security_hardening.sql's version, adding the two
-- sync columns to what a client can't set (a seller clearing their own
-- alert would hide it until the next run).
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
    new.supplier_checked_at := null;
    new.supplier_alert := null;
    return new;
  end if;
  if new.store_id is distinct from old.store_id
     or new.id is distinct from old.id
     or new.created_at is distinct from old.created_at then
    raise exception 'listing store, id and creation time are immutable' using errcode = '42501';
  end if;
  new.sold_count := old.sold_count;
  new.rating := old.rating;
  new.supplier_checked_at := old.supplier_checked_at;
  new.supplier_alert := old.supplier_alert;
  return new;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed: listing sync not scheduled';
    return;
  end if;
  -- Hourly: re-checks a batch of listed products against CJ.
  perform cron.schedule('sellora-sync-listings', '50 * * * *',
    $job$ select public.invoke_scheduled_job('syncListings') $job$);
end;
$$;
