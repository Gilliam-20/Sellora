/**
 * Refunds.
 *
 * Dropshipping guarantees a steady trickle of orders that are paid for and
 * cannot be fulfilled - CJ runs out of stock, the wallet is empty, the
 * customer's address is undeliverable. Without this the only recourse is
 * refunding by hand in the IntaSend dashboard, which leaves our own order
 * row saying "paid" forever and no record of what was returned to whom.
 *
 * The decision is a pure function (`decideRefund`) so the money rules are
 * testable on their own; `refundOrder` does the provider call and the write.
 */

import { db, must } from "./db.js";
import * as intasend from "./intasendApi.js";
import { ALERTS, logAlert, logInfo } from "./logging.js";
import { getOrder } from "./orders.js";
import { millisOf } from "./time.js";

// A refund claim older than this is assumed orphaned - the invocation that
// took it timed out or crashed - and may be reclaimed. Deliberately longer
// than a provider call could plausibly take.
const REFUND_CLAIM_STALE_MS = 5 * 60 * 1000;

// Currency amounts are compared with a cent of slack, the same tolerance the
// payment-amount checks use.
const EPSILON = 0.01;

// Payment states money can conceivably be returned from.
const REFUNDABLE_PAYMENT_STATUSES = Object.freeze([
  "paid",
  "partially_refunded",
  "refunded",
]);

/**
 * What the customer was actually charged, in the currency the provider took
 * it in. IntaSend always settles KES (`totalKes`) whatever the shopper's
 * region.
 * @param {object} order Order.
 * @return {{amount: number, currency: string}|null} The charge, or null if
 *   the order has no provider we can refund through.
 */
function chargedAmount(order) {
  if (order.paymentProvider === "INTASEND") {
    return { amount: Number(order.totalKes), currency: "KES" };
  }
  return null;
}

/**
 * Whether this order can be refunded right now, and for how much.
 *
 * Refusals are returned rather than thrown so the endpoint can turn each
 * into a specific message - "already refunded" and "not paid" want different
 * answers from a support agent's point of view.
 * @param {object} order Order.
 * @param {{amount: (number|undefined), now: (number|undefined)}=} opts
 *   `amount` requests a partial refund; omitted means refund what's left.
 * @return {{ok: boolean, reason: string, amount: (number|undefined),
 *   currency: (string|undefined), provider: (string|undefined),
 *   full: (boolean|undefined), cancelOrder: (boolean|undefined)}} Decision.
 */
function decideRefund(order, { amount, now = Date.now() } = {}) {
  // "refunded" is included deliberately: it reaches the remaining-amount
  // check below and is refused as `already_refunded`, which is what a
  // support agent needs to hear. Refusing it here would tell them the order
  // was never paid, which is both wrong and alarming.
  if (!REFUNDABLE_PAYMENT_STATUSES.includes(order.paymentStatus)) {
    return { ok: false, reason: "not_paid" };
  }

  const charge = chargedAmount(order);
  if (!charge || !Number.isFinite(charge.amount) || charge.amount <= 0) {
    return { ok: false, reason: "no_charge_to_refund" };
  }

  // A live claim from a concurrent refund. Only reclaim once it's stale -
  // otherwise this is a second click on the same button and would refund the
  // customer twice.
  if (order.refundStatus === "PROCESSING") {
    if (now - millisOf(order.refundClaimedAt) < REFUND_CLAIM_STALE_MS) {
      return { ok: false, reason: "refund_in_progress" };
    }
  }

  const refunded = Number(order.refundedAmount) || 0;
  const remaining = Math.round((charge.amount - refunded) * 100) / 100;
  if (remaining <= EPSILON) return { ok: false, reason: "already_refunded" };

  const requested = amount == null ?
    remaining :
    Math.round(Number(amount) * 100) / 100;
  if (!Number.isFinite(requested) || requested <= 0) {
    return { ok: false, reason: "invalid_amount" };
  }
  if (requested - remaining > EPSILON) {
    return { ok: false, reason: "exceeds_remaining" };
  }

  const full = Math.abs(requested - remaining) <= EPSILON && refunded === 0;
  return {
    ok: true,
    reason: "refundable",
    amount: requested,
    currency: charge.currency,
    provider: order.paymentProvider,
    full,
    // An order already on its way from CJ stays a live order - the goods
    // exist and someone has to handle the return. Only one that never
    // reached CJ is cancelled outright by refunding it.
    cancelOrder: full && order.cjOrderStatus !== "PUSHED",
  };
}

/**
 * The order fields a completed refund writes.
 * @param {object} order Order as it was before the refund.
 * @param {object} decision Output of `decideRefund`.
 * @return {{refundedAmount: number, paymentStatus: string,
 *   status: (string|undefined)}} The new money-state of the order.
 */
function refundedState(order, decision) {
  const refunded = Math.round(
      ((Number(order.refundedAmount) || 0) + decision.amount) * 100) / 100;
  const charge = chargedAmount(order);
  const fullyRefunded = charge ?
    charge.amount - refunded <= EPSILON :
    decision.full;
  const state = {
    refundedAmount: refunded,
    paymentStatus: fullyRefunded ? "refunded" : "partially_refunded",
  };
  if (decision.cancelOrder) state.status = "cancelled";
  return state;
}

/**
 * Refunds an order through whichever provider took the money.
 *
 * The order is claimed before the provider is called - a compare-and-set on
 * the refund state it was decided from, so two support agents clicking
 * refund at the same moment can't both issue one. If the provider call
 * fails the claim is released and the money-state is left exactly as it
 * was - a refund is only ever recorded after the provider has confirmed it.
 * @param {object} input Refund request.
 * @param {string} input.orderId Order id.
 * @param {number=} input.amount Partial amount; omitted refunds the rest.
 * @param {string=} input.reason Provider reason code.
 * @param {string=} input.comment Free-text note kept on the refund record.
 * @param {string=} input.actorUid Who asked for it, for the audit trail.
 * @return {Promise<object>} `{ ok, reason, ... }` - `ok: false` carries the
 *   refusal reason from `decideRefund`.
 */
async function refundOrder({ orderId, amount, reason, comment, actorUid }) {
  const order = await getOrder(orderId);
  const decision = decideRefund(order, { amount });
  if (!decision.ok) return decision;

  const claimed = must(await db().from("orders").update({
    refund_status: "PROCESSING",
    refund_claimed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  })
      .eq("id", orderId)
      .eq("refund_status", order.refundStatus)
      .eq("refunded_amount", order.refundedAmount || 0)
      .select("id"));
  if (claimed.length === 0) {
    return { ok: false, reason: "refund_in_progress" };
  }

  let result;
  try {
    result = await callProvider(order, decision, { reason, comment });
  } catch (err) {
    // Release the claim so the refund can be retried once whatever the
    // provider objected to is fixed, and record why it failed - a refund
    // that didn't happen is money still owed to a customer.
    must(await db().from("orders").update({
      refund_status: "FAILED",
      refund_error: String(err.message || err).slice(0, 1000),
      updated_at: new Date().toISOString(),
    }).eq("id", orderId));
    logAlert(ALERTS.REFUND_FAILED, {
      orderId,
      uid: order.uid,
      provider: decision.provider,
      amount: decision.amount,
      currency: decision.currency,
      actorUid,
    }, err);
    throw err;
  }

  const state = refundedState(order, decision);
  const update = {
    refunded_amount: state.refundedAmount,
    payment_status: state.paymentStatus,
    refund_status: "REFUNDED",
    refund_error: null,
    refund_currency: decision.currency,
    // Safe as a read-modify-write: the claim above means no other refund
    // can be writing this row now.
    refunds: [...(Array.isArray(order.refunds) ? order.refunds : []), {
      amount: decision.amount,
      currency: decision.currency,
      provider: decision.provider,
      providerRefundId: result.refundId,
      providerStatus: result.status,
      reason: reason || null,
      comment: comment || null,
      actorUid: actorUid || null,
      createdAt: new Date().toISOString(),
    }],
    updated_at: new Date().toISOString(),
  };
  if (state.status) update.status = state.status;
  must(await db().from("orders").update(update).eq("id", orderId));

  // The orders audit trigger records the state change, but only this path
  // knows which admin asked for it. The refund has already happened, so a
  // failed audit write is logged loudly rather than reported as a failed
  // refund.
  try {
    must(await db().from("audit_logs").insert({
      actor_id: actorUid || null,
      actor_role: "admin",
      action: "order.refund",
      entity_type: "order",
      entity_id: orderId,
      details: {
        amount: decision.amount,
        currency: decision.currency,
        provider: decision.provider,
        providerRefundId: result.refundId,
        full: decision.full,
        reason: reason || null,
      },
    }));
  } catch (err) {
    logAlert(ALERTS.ORDER_NEEDS_RECONCILIATION, {
      orderId, actorUid, reason: "refund_audit_write_failed",
    }, err);
  }

  logInfo("order_refunded", {
    orderId,
    uid: order.uid,
    provider: decision.provider,
    amount: decision.amount,
    currency: decision.currency,
    full: decision.full,
    providerRefundId: result.refundId,
    actorUid,
  });

  return {
    ok: true,
    reason: "refunded",
    ...state,
    amount: decision.amount,
    currency: decision.currency,
    providerRefundId: result.refundId,
    providerStatus: result.status,
  };
}

/**
 * Issues the refund with the provider that took the payment.
 * @param {object} order Order.
 * @param {object} decision Output of `decideRefund`.
 * @param {{reason: (string|undefined), comment: (string|undefined)}} opts
 *   Reason passed through to the provider.
 * @return {Promise<{refundId: (string|null), status: string}>} Provider ids.
 */
async function callProvider(order, decision, { reason, comment }) {
  if (decision.provider === "INTASEND") {
    const invoiceId = order.paymentRef?.invoiceId;
    if (!invoiceId) {
      throw new Error(
          "This order has no IntaSend invoice to refund - refund it from the " +
          "IntaSend dashboard and record it manually");
    }
    return intasend.refundPayment({
      invoiceId,
      amount: decision.amount,
      reason,
      comment,
    });
  }
  throw new Error(`Cannot refund a ${decision.provider || "unknown"} payment`);
}

export {
  refundOrder,
  decideRefund,
  refundedState,
  chargedAmount,
  REFUND_CLAIM_STALE_MS,
};
