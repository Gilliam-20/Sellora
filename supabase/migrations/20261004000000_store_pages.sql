-- TODO §20: the storefront's own pages. About, Contact and the four policies
-- (privacy, terms, shipping, refunds) are written by the seller and shown at
-- /s/{slug}/pages/{kind}. They live apart from the design document: they're
-- text a seller keeps up to date, not layout, and the policies must be
-- reachable even if the design never changes.
--
-- Nothing is published on the seller's behalf. The app offers editable
-- templates, but a page exists only once the seller saves it.

create table public.store_pages (
  store_id text not null references public.stores (id) on delete cascade,
  kind text not null
    constraint store_pages_kind check (
      kind in ('about', 'contact', 'privacy', 'terms', 'shipping', 'refund')),
  title text not null
    constraint store_pages_title check (char_length(btrim(title)) between 1 and 80),
  body text not null default ''
    constraint store_pages_body check (char_length(body) <= 20000),
  -- Contact details, shown on the contact page only.
  email text
    constraint store_pages_email check (
      email is null or (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  phone text
    constraint store_pages_phone check (phone is null or phone ~ '^\+?[0-9 ()-]{6,20}$'),
  is_published boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (store_id, kind),
  constraint store_pages_contact_only check (
    kind = 'contact' or (email is null and phone is null))
);

alter table public.store_pages enable row level security;

create policy "store_pages: owner or admin reads"
  on public.store_pages for select
  using (public.owns_store(store_id) or (select public.is_admin()));

create policy "store_pages: owner creates"
  on public.store_pages for insert
  with check (public.owns_store(store_id));

create policy "store_pages: owner edits"
  on public.store_pages for update
  using (public.owns_store(store_id))
  with check (public.owns_store(store_id));

create policy "store_pages: owner deletes"
  on public.store_pages for delete
  using (public.owns_store(store_id));

revoke insert, update on public.store_pages from anon, authenticated;
grant insert (store_id, kind, title, body, email, phone, is_published)
  on public.store_pages to authenticated;
grant update (title, body, email, phone, is_published)
  on public.store_pages to authenticated;

create or replace function public.store_pages_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger store_pages_touch
  before insert or update on public.store_pages
  for each row execute function public.store_pages_touch();

-- What buyers read: published pages of open storefronts, the same standing
-- rule as storefront_products and storefront_designs.
create or replace view public.storefront_pages with (security_barrier = true) as
select p.store_id, p.kind, p.title, p.body, p.email, p.phone, p.updated_at
from public.store_pages p
join public.stores s on s.id = p.store_id
where p.is_published
  and not s.is_suspended
  and public.seller_can_sell(s.seller_id);

revoke all on public.storefront_pages from public, anon, authenticated;
grant select on public.storefront_pages to anon, authenticated;
