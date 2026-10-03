-- TODO §17: the seller billing page. Cancel and resume, a saved payment
-- method, numbered invoices, and renewal reminders.
--
-- There is no automatic renewal: every period is a payment the seller
-- starts (M-Pesa STK push or IntaSend's card page). So "cancel" can't stop a
-- charge. It records that the seller doesn't mean to renew: the plan keeps
-- working to the end of the paid period, renewal reminders stop, and the
-- billing page says it's ending. "Resume" undoes that while the period is
-- still running. Paying again resumes too (activate_subscription clears the
-- flag), so a cancelled seller who changes their mind just renews.

-- ---------------------------------------------------------------------------
-- Subscriptions: cancel at period end, reminder bookkeeping
-- ---------------------------------------------------------------------------

alter table public.subscriptions
  add column cancel_at_period_end boolean not null default false,
  add column cancelled_at timestamptz,
  add column cancel_reason text
    constraint subscriptions_cancel_reason_length check (char_length(cancel_reason) <= 500),
  -- The current_period_end a renewal reminder was last sent for, so the
  -- daily job sends one per period and a renewal (a new end) re-arms it.
  add column renewal_reminder_for timestamptz;

-- ---------------------------------------------------------------------------
-- billing_history: invoice numbers and the period each payment bought
-- ---------------------------------------------------------------------------

alter table public.billing_history
  add column invoice_number text constraint billing_history_invoice_number_key unique,
  add column period_start timestamptz,
  add column period_end timestamptz;

create sequence public.billing_invoice_seq;

-- An invoice exists once money has been taken: the number is assigned on
-- the move to 'paid' and never changes. Numbers are sequential across the
-- platform (gaps only if a transaction rolls back), INV-<year paid>-NNNNNN.
create or replace function public.billing_assign_invoice_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'paid' and new.invoice_number is null then
    new.invoice_number := 'INV-' || to_char(coalesce(new.paid_at, now()) at time zone 'UTC', 'YYYY')
      || '-' || lpad(nextval('public.billing_invoice_seq')::text, 6, '0');
  elsif tg_op = 'UPDATE' and old.invoice_number is not null
        and new.invoice_number is distinct from old.invoice_number then
    raise exception 'an invoice number cannot change' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger billing_assign_invoice_number
  before insert or update on public.billing_history
  for each row execute function public.billing_assign_invoice_number();

revoke execute on function public.billing_assign_invoice_number() from public, anon, authenticated;

-- Payments made before this migration get their numbers in payment order.
-- Their period is the one recorded on the subscription when it's the
-- latest payment; older ones never stored it, so it stays null.
do $$
declare
  e record;
begin
  for e in select id from public.billing_history
           where status = 'paid' and invoice_number is null
           order by paid_at nulls last, created_at, id
  loop
    update public.billing_history set invoice_number = null where id = e.id;
  end loop;
end;
$$;

update public.billing_history b
set period_start = s.current_period_start, period_end = s.current_period_end
from public.subscriptions s
where s.last_billing_history_id = b.id and b.period_end is null;

-- Was 20260928000000_security_hardening.sql's. Now also records on the
-- entry which period it paid for (the invoice shows it), and clears a
-- cancellation: paying for another period means the seller is staying.
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
  entry_start timestamptz;
  entry_end timestamptz;
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
    entry_start := existing.current_period_end;
  else
    period_start := paid_time;
    period_end := paid_time + make_interval(days => entry.billing_period_days);
    entry_start := paid_time;
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
    updated_at = excluded.updated_at,
    cancel_at_period_end = false,
    cancelled_at = null,
    cancel_reason = null;

  -- period_end is also a billing_history column, so the variable can't be
  -- named inside that statement.
  entry_end := period_end;
  update public.billing_history
  set period_start = entry_start, period_end = entry_end
  where id = entry.id;

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

revoke execute on function public.activate_subscription(text, text) from public, anon, authenticated;
grant execute on function public.activate_subscription(text, text) to service_role;

-- ---------------------------------------------------------------------------
-- Cancel / resume (the signed-in seller's own subscription)
-- ---------------------------------------------------------------------------

create or replace function public.cancel_my_subscription(p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  sub public.subscriptions;
  reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if v_uid is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  select * into sub from public.subscriptions where seller_id = v_uid for update;
  if not found or sub.status <> 'active' or sub.current_period_end <= now() then
    raise exception 'There is no running subscription to cancel' using errcode = 'P0002';
  end if;
  if char_length(reason) > 500 then
    raise exception 'Keep the reason under 500 characters' using errcode = '22001';
  end if;
  if sub.cancel_at_period_end then
    return jsonb_build_object('cancelAtPeriodEnd', true, 'currentPeriodEnd', sub.current_period_end);
  end if;

  update public.subscriptions
  set cancel_at_period_end = true, cancelled_at = now(), cancel_reason = reason, updated_at = now()
  where seller_id = v_uid;
  perform public.write_audit('subscription.cancel', 'profile', v_uid::text,
    jsonb_build_object('planId', sub.plan_id, 'currentPeriodEnd', sub.current_period_end,
                       'reason', reason));
  return jsonb_build_object('cancelAtPeriodEnd', true, 'currentPeriodEnd', sub.current_period_end);
end;
$$;

create or replace function public.resume_my_subscription()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  sub public.subscriptions;
begin
  if v_uid is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  select * into sub from public.subscriptions where seller_id = v_uid for update;
  if not found or sub.status <> 'active' or sub.current_period_end <= now() then
    raise exception 'This subscription has ended. Renew it to keep selling.' using errcode = 'P0002';
  end if;
  if sub.cancel_at_period_end then
    update public.subscriptions
    set cancel_at_period_end = false, cancelled_at = null, cancel_reason = null, updated_at = now()
    where seller_id = v_uid;
    perform public.write_audit('subscription.resume', 'profile', v_uid::text,
      jsonb_build_object('planId', sub.plan_id, 'currentPeriodEnd', sub.current_period_end));
  end if;
  return jsonb_build_object('cancelAtPeriodEnd', false, 'currentPeriodEnd', sub.current_period_end);
end;
$$;

revoke execute on function public.cancel_my_subscription(text) from public, anon;
revoke execute on function public.resume_my_subscription() from public, anon;
grant execute on function public.cancel_my_subscription(text) to authenticated;
grant execute on function public.resume_my_subscription() to authenticated;

-- ---------------------------------------------------------------------------
-- Usage: now also the cancellation and the period start
-- ---------------------------------------------------------------------------

-- Was 20260929000000_billing_usage.sql's, with cancelAtPeriodEnd,
-- cancelledAt and currentPeriodStart added.
create or replace function public.my_plan_usage()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  sub public.subscriptions;
  pl public.subscription_plans;
  v_plan_id text;
  paid_orders integer;
begin
  if v_uid is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;
  select * into sub from public.subscriptions where seller_id = v_uid;
  v_plan_id := coalesce(sub.plan_id,
    (select subscription_plan_id from public.profiles where uid = v_uid));
  select * into pl from public.subscription_plans where id = v_plan_id;

  select count(*) into paid_orders
  from public.orders
  where seller_id = v_uid
    and payment_status in ('paid', 'partially_refunded', 'refunded')
    and created_at > now() - make_interval(days => coalesce(pl.billing_period_days, 30));

  return jsonb_build_object(
    'planId', v_plan_id,
    'subscriptionStatus', case
      when sub.seller_id is null then 'none'
      when sub.status = 'active' and sub.current_period_end > now() then 'active'
      when sub.status = 'active' then 'lapsed'
      else sub.status end,
    'currentPeriodStart', sub.current_period_start,
    'currentPeriodEnd', sub.current_period_end,
    'cancelAtPeriodEnd', coalesce(sub.cancel_at_period_end, false),
    'cancelledAt', sub.cancelled_at,
    'billingPeriodDays', coalesce(pl.billing_period_days, 30),
    'listingCount', (select count(*) from public.products where seller_id = v_uid and is_listed),
    'listingLimit', coalesce(pl.listing_limit, -1),
    'orderCount', paid_orders,
    'orderLimit', coalesce(sub.order_limit, pl.order_limit, -1),
    'storeCount', (select count(*) from public.stores where seller_id = v_uid),
    'storeLimit', coalesce(pl.store_limit, 1));
end;
$$;

revoke execute on function public.my_plan_usage() from public, anon;
grant execute on function public.my_plan_usage() to authenticated;

-- ---------------------------------------------------------------------------
-- Saved payment method and invoice details
-- ---------------------------------------------------------------------------

-- What the billing page prefills when the seller pays. No card data: a
-- card payment always goes through IntaSend's hosted page, so 'card' only
-- means "take me there". The M-Pesa number is stored the way the payment
-- route sends it (2547XXXXXXXX / 2541XXXXXXXX). The name and tax PIN are
-- printed on invoices when set.
create table public.seller_billing_profiles (
  seller_id uuid primary key references public.profiles (uid) on delete cascade,
  payment_method text not null default 'mpesa'
    constraint seller_billing_profiles_method check (payment_method in ('mpesa', 'card')),
  mpesa_phone text
    constraint seller_billing_profiles_phone check (mpesa_phone ~ '^254[17][0-9]{8}$'),
  billing_name text
    constraint seller_billing_profiles_name check (char_length(billing_name) between 1 and 120),
  tax_id text
    constraint seller_billing_profiles_tax_id check (char_length(tax_id) between 1 and 40),
  updated_at timestamptz not null default now(),
  constraint seller_billing_profiles_mpesa_needs_phone
    check (payment_method <> 'mpesa' or mpesa_phone is not null)
);

alter table public.seller_billing_profiles enable row level security;

create policy "seller_billing_profiles: owner or admin reads"
  on public.seller_billing_profiles for select
  using (seller_id = (select auth.uid()) or (select public.is_admin()));

create policy "seller_billing_profiles: seller creates their own"
  on public.seller_billing_profiles for insert
  with check (
    seller_id = (select auth.uid())
    and exists (select 1 from public.profiles p
                where p.uid = (select auth.uid()) and p.role = 'seller'));

create policy "seller_billing_profiles: seller edits their own"
  on public.seller_billing_profiles for update
  using (seller_id = (select auth.uid()))
  with check (seller_id = (select auth.uid()));

create or replace function public.seller_billing_profiles_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger seller_billing_profiles_touch
  before insert or update on public.seller_billing_profiles
  for each row execute function public.seller_billing_profiles_touch();

-- ---------------------------------------------------------------------------
-- Renewal reminders
-- ---------------------------------------------------------------------------

-- Daily: one notification per period to each seller whose paid time ends
-- within three days, unless they've cancelled. Returns how many it sent.
create or replace function public.send_renewal_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  sent integer;
begin
  with due as (
    update public.subscriptions s
    set renewal_reminder_for = s.current_period_end
    where s.status = 'active'
      and not s.cancel_at_period_end
      and s.current_period_end > now()
      and s.current_period_end <= now() + interval '3 days'
      and s.renewal_reminder_for is distinct from s.current_period_end
    returning s.seller_id, s.current_period_end, s.plan_id)
  insert into public.notifications (recipient_id, title, message)
  select d.seller_id,
         'Your plan ends soon',
         'Your ' || coalesce(p.name, d.plan_id) || ' plan ends on '
           || to_char(d.current_period_end at time zone 'Africa/Nairobi', 'FMDD Mon YYYY')
           || '. Renew from Subscription & billing to keep your store open.'
  from due d
  left join public.subscription_plans p on p.id = d.plan_id;
  get diagnostics sent = row_count;
  return sent;
end;
$$;

revoke execute on function public.send_renewal_reminders() from public, anon, authenticated;
grant execute on function public.send_renewal_reminders() to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed: renewal reminders not scheduled';
    return;
  end if;
  perform cron.schedule('sellora-renewal-reminders', '0 6 * * *',
    $job$ select public.send_renewal_reminders() $job$);
end;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion clears the billing profile
-- ---------------------------------------------------------------------------

-- Was 20260928000000_security_hardening.sql's; a seller's saved M-Pesa
-- number, invoice name and tax PIN are personal data too.
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
  delete from public.seller_billing_profiles where seller_id = p_uid;

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

revoke execute on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;
