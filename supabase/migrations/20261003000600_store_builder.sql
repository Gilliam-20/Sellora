-- TODO §18: the store builder. Each store's storefront is a design document
-- (theme settings, announcement bar, navigation, homepage sections with
-- their blocks, footer) instead of one hard-coded layout. The seller edits a
-- draft; publishing copies it to what buyers see. The document's shape is
-- defined and validated by the app (lib/data/models/store_design.dart);
-- the database bounds its size and keeps draft and published apart.

-- ---------------------------------------------------------------------------
-- Designs
-- ---------------------------------------------------------------------------

create table public.store_designs (
  store_id text primary key references public.stores (id) on delete cascade,
  draft jsonb not null default '{}'::jsonb
    constraint store_designs_draft_object check (jsonb_typeof(draft) = 'object')
    constraint store_designs_draft_size check (pg_column_size(draft) <= 131072),
  draft_updated_at timestamptz not null default now(),
  -- Written only by publish_store_design().
  published jsonb
    constraint store_designs_published_object check (jsonb_typeof(published) = 'object'),
  published_at timestamptz,
  published_version integer not null default 0
);

alter table public.store_designs enable row level security;

-- The draft is the seller's work in progress: only they and admin see it.
-- Buyers read the published design through storefront_designs.
create policy "store_designs: owner or admin reads"
  on public.store_designs for select
  using (public.owns_store(store_id) or (select public.is_admin()));

create policy "store_designs: owner creates"
  on public.store_designs for insert
  with check (public.owns_store(store_id));

create policy "store_designs: owner edits the draft"
  on public.store_designs for update
  using (public.owns_store(store_id))
  with check (public.owns_store(store_id));

-- Clients may write the draft and nothing else; publishing goes through
-- the function, which also records who published what.
revoke insert, update on public.store_designs from anon, authenticated;
grant insert (store_id, draft) on public.store_designs to authenticated;
grant update (draft) on public.store_designs to authenticated;

create or replace function public.store_designs_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.draft is distinct from old.draft then
    new.draft_updated_at := now();
  end if;
  return new;
end;
$$;

create trigger store_designs_touch
  before insert or update on public.store_designs
  for each row execute function public.store_designs_touch();

-- Publishes the store's draft. The store's accent color follows the
-- design's, so the screens that still read stores.primary_color_hex (the
-- category chips, the seller dashboard) match the storefront.
create or replace function public.publish_store_design(p_store_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.store_designs;
  sections jsonb;
  accent text;
begin
  if not public.owns_store(p_store_id) then
    raise exception 'Only the store owner can publish its design' using errcode = '42501';
  end if;
  select * into d from public.store_designs where store_id = p_store_id for update;
  if not found then
    raise exception 'Save a design before publishing it' using errcode = 'P0002';
  end if;
  sections := d.draft -> 'sections';
  if sections is null or jsonb_typeof(sections) <> 'array' then
    raise exception 'The design has no sections' using errcode = '22023';
  end if;
  if jsonb_array_length(sections) > 40 then
    raise exception 'A homepage can have at most 40 sections' using errcode = '22023';
  end if;

  update public.store_designs
  set published = draft, published_at = now(), published_version = published_version + 1
  where store_id = p_store_id
  returning * into d;

  accent := d.published #>> '{theme,colors,accent}';
  if accent ~ '^#[0-9A-Fa-f]{6}$' then
    update public.stores set primary_color_hex = upper(accent)
    where id = p_store_id and primary_color_hex is distinct from upper(accent);
  end if;

  perform public.write_audit('store.design_publish', 'store', p_store_id,
    jsonb_build_object('version', d.published_version,
                       'sections', jsonb_array_length(sections)));
  return jsonb_build_object('version', d.published_version, 'publishedAt', d.published_at);
end;
$$;

revoke execute on function public.publish_store_design(text) from public, anon;
grant execute on function public.publish_store_design(text) to authenticated;

-- What buyers read: published designs of storefronts that are open, the
-- same standing rule storefront_products applies.
create or replace view public.storefront_designs with (security_barrier = true) as
select d.store_id, d.published as design, d.published_at, d.published_version
from public.store_designs d
join public.stores s on s.id = d.store_id
where d.published is not null
  and not s.is_suspended
  and public.seller_can_sell(s.seller_id);

revoke all on public.storefront_designs from public, anon, authenticated;
grant select on public.storefront_designs to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Newsletter sign-ups (the newsletter section)
-- ---------------------------------------------------------------------------

-- Collected for the seller to export; Sellora sends nothing to them.
create table public.newsletter_subscribers (
  id bigint generated always as identity primary key,
  store_id text not null references public.stores (id) on delete cascade,
  email text not null
    constraint newsletter_subscribers_email check (
      char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  created_at timestamptz not null default now(),
  constraint newsletter_subscribers_unique unique (store_id, email)
);

alter table public.newsletter_subscribers enable row level security;

create policy "newsletter_subscribers: owner or admin reads"
  on public.newsletter_subscribers for select
  using (public.owns_store(store_id) or (select public.is_admin()));

-- The seller removes someone who asks to be taken off.
create policy "newsletter_subscribers: owner deletes"
  on public.newsletter_subscribers for delete
  using (public.owns_store(store_id));

revoke insert, update on public.newsletter_subscribers from anon, authenticated;

-- Anyone on an open storefront may sign up. Signing up twice is a quiet
-- no-op, so the answer never reveals whether an address is on the list.
-- Rate limited per store, since anonymous callers have no other key.
create or replace function public.subscribe_to_store_newsletter(p_store_id text, p_email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  allowed boolean;
begin
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.stores s
    where s.id = p_store_id and not s.is_suspended and public.seller_can_sell(s.seller_id)
  ) then
    raise exception 'This store is not taking sign-ups' using errcode = 'P0002';
  end if;
  select r.allowed into allowed
  from public.consume_rate_limit('newsletter:' || p_store_id, 60, 3600000) r;
  if not allowed then
    raise exception 'Too many sign-ups right now. Try again later.' using errcode = '54000';
  end if;
  insert into public.newsletter_subscribers (store_id, email)
  values (p_store_id, v_email)
  on conflict on constraint newsletter_subscribers_unique do nothing;
  return true;
end;
$$;

revoke execute on function public.subscribe_to_store_newsletter(text, text) from public;
grant execute on function public.subscribe_to_store_newsletter(text, text) to anon, authenticated;
