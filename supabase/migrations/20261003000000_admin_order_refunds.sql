-- Refund state for the admin Orders screen (implementation plan PHASE 8).
--
-- `/refundOrder` is admin-only, but what an admin needs to decide on a
-- refund - the amount actually charged (`total_kes`; IntaSend settles KES
-- whatever the shopper's currency), the refund state machine and the refund
-- history - lives in server-only `orders` columns. Rather than widening the
-- column grant every client shares, this view exposes just those columns,
-- and only to admin. Like `seller_orders` it runs as its owner, so the
-- `where` clause is the whole access check.

create view public.admin_order_refunds with (security_barrier = true) as
select
  o.id, o.payment_provider, o.payment_status, o.total_kes, o.refunded_amount,
  o.refund_status, o.refund_error, o.refund_currency, o.refunds,
  o.cj_order_status
from public.orders o
where (select public.is_admin());

revoke all on public.admin_order_refunds from public, anon, authenticated;
grant select on public.admin_order_refunds to authenticated;
