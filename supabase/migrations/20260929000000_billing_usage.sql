-- Billing (implementation plan PHASE 3): what the seller's subscription
-- screen reads, and plan downgrades that can't keep more listings than the
-- new plan allows. See SELLORA_SECURITY_AUDIT.md §7.

-- ---------------------------------------------------------------------------
-- Usage against the plan, counted the way the server enforces it
-- ---------------------------------------------------------------------------

-- The caller's usage: listed products as products_enforce_listing_limit
-- counts them, paid orders over the rolling billing period as
-- seller_order_gate counts them, and stores as seller_can_add_store does.
-- The app used to count orders itself, unpaid ones included, against the
-- plan's current limit rather than the subscription's snapshot, so its
-- "limit reached" could disagree with what checkout actually refused.
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
    'currentPeriodEnd', sub.current_period_end,
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
-- Downgrades: listings above the new plan's cap come down
-- ---------------------------------------------------------------------------

-- products_enforce_listing_limit only stops new publishes, so without this
-- a seller could buy the top plan for one period, list everything, then
-- drop to the cheapest plan and keep it all listed. subscribeSeller refuses
-- such a downgrade up front; this catches the race where the seller lists
-- more between starting the payment and paying. The money is already
-- taken by then, so it unlists the newest excess instead of refusing, and
-- records that it did.
create or replace function public.subscriptions_enforce_listing_cap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cap integer;
  excess integer;
  unlisted integer;
begin
  if tg_op = 'UPDATE' and new.plan_id is not distinct from old.plan_id then
    return new;
  end if;
  select listing_limit into cap from public.subscription_plans where id = new.plan_id;
  if cap is null or cap < 0 then
    return new;
  end if;
  select count(*) - cap into excess
  from public.products where seller_id = new.seller_id and is_listed;
  if excess <= 0 then
    return new;
  end if;

  with newest as (
    select store_id, id from public.products
    where seller_id = new.seller_id and is_listed
    order by created_at desc, id desc
    limit excess)
  update public.products p set is_listed = false
  from newest n
  where p.store_id = n.store_id and p.id = n.id;
  get diagnostics unlisted = row_count;

  perform public.write_audit('subscription.listings_unlisted', 'profile', new.seller_id::text,
    jsonb_build_object('planId', new.plan_id, 'listingLimit', cap, 'unlisted', unlisted));
  return new;
end;
$$;

create trigger subscriptions_enforce_listing_cap
  after insert or update of plan_id on public.subscriptions
  for each row execute function public.subscriptions_enforce_listing_cap();

revoke execute on function public.subscriptions_enforce_listing_cap() from public, anon, authenticated;
